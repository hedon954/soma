import type {
  AgentEvent,
  AgentJob,
} from "./domain.js";
import { ProtocolError } from "./domain.js";
import type {
  ManagedModelProvider,
  ProviderMedia,
  ProviderStep,
} from "./worker.js";
import {
  deviceToolRegistry,
  effectiveAllowedDeviceTools,
} from "./tool-registry.js";

interface ChatCompletionResponse {
  choices?: {
    message?: {
      content?: string | null;
      tool_calls?: {
        id?: string;
        function?: {
          name?: string;
          arguments?: string;
        };
      }[];
    };
  }[];
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
}

interface ChatCompletionStreamChunk {
  choices?: {
    delta?: {
      content?: string | null;
      tool_calls?: {
        index?: number;
        id?: string;
        function?: {
          name?: string;
          arguments?: string;
        };
      }[];
    };
  }[];
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
}

export class OpenAICompatibleManagedProvider implements ManagedModelProvider {
  constructor(
    private readonly baseURL: string,
    private readonly apiKey: string,
    private readonly model: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async run(
    job: AgentJob,
    events: AgentEvent[],
    media: ProviderMedia[],
    onTextDelta?: (delta: string) => Promise<void>,
  ): Promise<ProviderStep> {
    if (job.input === undefined) {
      throw new ProtocolError("job_expired", "任务内容已清理。", 410);
    }
    const directVideo = supportsDirectVideo(this.model);
    const messages: Record<string, unknown>[] = [
      {
        role: "system",
        content:
          "你是 Soma 的远程执行 Agent。只依据当前任务最小上下文工作；需要设备数据或写入时调用允许的固定设备 Tool。不要输出思维过程。",
      },
      userMessage(job.input.text, job.input.contextSnapshot, media, directVideo),
    ];
    for (const event of events) {
      if (
        event.kind === "tool" &&
        event.phase === "suspended" &&
        typeof event.payload.toolCallID === "string" &&
        typeof event.payload.toolName === "string"
      ) {
        messages.push({
          role: "assistant",
          content: null,
          tool_calls: [
            {
              id: event.payload.toolCallID,
              type: "function",
              function: {
                name: event.payload.toolName,
                arguments: JSON.stringify(event.payload.arguments ?? {}),
              },
            },
          ],
        });
      } else if (
        event.kind === "tool" &&
        event.phase === "completed" &&
        typeof event.payload.toolCallID === "string"
      ) {
        messages.push({
          role: "tool",
          tool_call_id: event.payload.toolCallID,
          content: JSON.stringify(event.payload.result ?? {}),
        });
      }
    }
    const allowedDeviceTools = effectiveAllowedDeviceTools(
      job.input.allowedDeviceTools,
      events,
    );
    const tools = allowedDeviceTools.flatMap((name) => {
      const definition = deviceToolRegistry.get(name);
      return definition === undefined
        ? []
        : [{
            type: "function",
            function: {
              name,
              description:
                definition.description ??
                "由用户设备执行的 Soma 固定 Tool；只传当前任务明确需要的最小参数。",
              parameters: definition.parameters,
            },
          }];
    });
    const mediaMode = directVideo && media.some((item) => item.contentType.startsWith("video/"))
      ? "direct_video"
      : media.some((item) => item.contentType.startsWith("image/"))
        ? "images"
        : "text";
    const maximumRequestAttempts = mediaMode === "direct_video" ||
        (job.input.requestAttempt ?? 1) > 1
      ? 1
      : 2;
    let lastError: unknown;
    for (let attempt = 1; attempt <= maximumRequestAttempts; attempt += 1) {
      const deadline = new ProviderRequestDeadline(mediaMode);
      try {
        const response = await this.fetcher(
          `${this.baseURL.replace(/\/$/, "")}/chat/completions`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${this.apiKey}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              model: this.model,
              messages,
              tools,
              tool_choice: "auto",
              stream: true,
              stream_options: { include_usage: true },
            }),
            signal: deadline.signal,
          },
        );
        if (!response.ok) {
          throw new ProtocolError(
            "provider_unavailable",
            "模型服务暂时不可用。",
            503,
          );
        }
        let step: ProviderStep;
        if (response.headers.get("content-type")?.includes("text/event-stream")) {
          step = await this.consumeStream(
            response,
            onTextDelta,
            () => deadline.markMeaningfulDelta(),
          );
        } else {
          step = await this.consumeResponse(response, onTextDelta, deadline);
        }
        deadline.finish();
        return step;
      } catch (error) {
        deadline.finish();
        lastError = deadline.error(error);
        if (
          attempt < maximumRequestAttempts &&
          !deadline.receivedMeaningfulDelta &&
          isRetryable(lastError)
        ) {
          continue;
        }
        throw lastError;
      }
    }
    throw lastError;
  }

  private async consumeResponse(
    response: Response,
    onTextDelta: ((delta: string) => Promise<void>) | undefined,
    deadline: ProviderRequestDeadline,
  ): Promise<ProviderStep> {
    const payload = (await response.json()) as ChatCompletionResponse;
    const message = payload.choices?.[0]?.message;
    const tool = message?.tool_calls?.[0]?.function;
    if (tool?.name !== undefined) {
      deadline.markMeaningfulDelta();
      let argumentsValue: Record<string, unknown>;
      try {
        argumentsValue = JSON.parse(tool.arguments ?? "{}") as Record<
          string,
          unknown
        >;
      } catch {
        throw new ProtocolError(
          "invalid_request",
          "Provider 返回了无效 Tool 参数。",
          502,
        );
      }
      return {
        kind: "deviceTool",
        ...(message?.tool_calls?.[0]?.id === undefined
          ? {}
          : { toolCallID: message.tool_calls[0].id }),
        toolName: tool.name,
        schemaVersion: deviceToolRegistry.get(tool.name)?.schemaVersion ?? 1,
        arguments: argumentsValue,
        mutation: true,
      };
    }
    const answer = message?.content?.trim();
    if (answer === undefined || answer.length === 0) {
      throw new ProtocolError(
        "provider_unavailable",
        "模型没有返回结果。",
        502,
      );
    }
    deadline.markMeaningfulDelta();
    if (onTextDelta !== undefined) await onTextDelta(answer);
    return {
      kind: "completed",
      answer,
      usage: {
        input: payload.usage?.prompt_tokens ?? 0,
        output: payload.usage?.completion_tokens ?? 0,
      },
    };
  }

  private async consumeStream(
    response: Response,
    onTextDelta?: (delta: string) => Promise<void>,
    onMeaningfulDelta?: () => void,
  ): Promise<ProviderStep> {
    if (response.body === null) {
      throw new ProtocolError(
        "provider_unavailable",
        "模型流没有返回内容。",
        502,
      );
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let answer = "";
    let usage = { input: 0, output: 0 };
    let firstTextEmitted = false;
    let bufferedText = "";
    let flushTimer: ReturnType<typeof setTimeout> | undefined;
    let emission = Promise.resolve();
    const toolCalls = new Map<
      number,
      { id?: string; name: string; arguments: string }
    >();

    const deliver = (text: string): Promise<void> => {
      if (onTextDelta === undefined || text.length === 0) return emission;
      emission = emission.then(() => onTextDelta(text));
      return emission;
    };
    const flushBufferedText = async (): Promise<void> => {
      if (flushTimer !== undefined) clearTimeout(flushTimer);
      flushTimer = undefined;
      const text = bufferedText;
      bufferedText = "";
      await deliver(text);
    };
    const projectText = async (text: string): Promise<void> => {
      if (!firstTextEmitted) {
        firstTextEmitted = true;
        await deliver(text);
        return;
      }
      bufferedText += text;
      if (
        bufferedText.length >= 48 ||
        /[\n。！？!?；;：:]$/.test(bufferedText)
      ) {
        await flushBufferedText();
      } else if (flushTimer === undefined) {
        flushTimer = setTimeout(() => {
          void flushBufferedText();
        }, 80);
      }
    };

    const consumeBlock = async (block: string): Promise<void> => {
      const data = block
        .split(/\r?\n/)
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice(5).trimStart())
        .join("\n");
      if (data.length === 0 || data === "[DONE]") return;
      let chunk: ChatCompletionStreamChunk;
      try {
        chunk = JSON.parse(data) as ChatCompletionStreamChunk;
      } catch {
        throw new ProtocolError(
          "provider_unavailable",
          "模型返回了无效流事件。",
          502,
        );
      }
      const delta = chunk.choices?.[0]?.delta;
      const content = delta?.content;
      if (typeof content === "string" && content.length > 0) {
        onMeaningfulDelta?.();
        answer += content;
        await projectText(content);
      }
      for (const toolDelta of delta?.tool_calls ?? []) {
        if (
          (toolDelta.id?.length ?? 0) > 0 ||
          (toolDelta.function?.name?.length ?? 0) > 0 ||
          (toolDelta.function?.arguments?.length ?? 0) > 0
        ) {
          onMeaningfulDelta?.();
        }
        const index = toolDelta.index ?? 0;
        const existing = toolCalls.get(index) ?? { name: "", arguments: "" };
        toolCalls.set(index, {
          ...(existing.id === undefined && toolDelta.id === undefined
            ? {}
            : { id: toolDelta.id ?? existing.id }),
          name: existing.name + (toolDelta.function?.name ?? ""),
          arguments:
            existing.arguments + (toolDelta.function?.arguments ?? ""),
        });
      }
      if (chunk.usage !== undefined) {
        usage = {
          input: chunk.usage.prompt_tokens ?? usage.input,
          output: chunk.usage.completion_tokens ?? usage.output,
        };
      }
    };

    for (;;) {
      const read = await reader.read();
      buffer += decoder.decode(read.value, { stream: !read.done });
      const blocks = buffer.split(/\r?\n\r?\n/);
      buffer = blocks.pop() ?? "";
      for (const block of blocks) await consumeBlock(block);
      if (read.done) break;
    }
    if (buffer.trim().length > 0) await consumeBlock(buffer);
    await flushBufferedText();
    await emission;

    const tool = [...toolCalls.entries()]
      .sort(([lhs], [rhs]) => lhs - rhs)
      .map(([, value]) => value)[0];
    if (tool !== undefined && tool.name.length > 0) {
      let argumentsValue: Record<string, unknown>;
      try {
        argumentsValue = JSON.parse(tool.arguments || "{}") as Record<
          string,
          unknown
        >;
      } catch {
        throw new ProtocolError(
          "invalid_request",
          "Provider 返回了无效 Tool 参数。",
          502,
        );
      }
      return {
        kind: "deviceTool",
        ...(tool.id === undefined ? {} : { toolCallID: tool.id }),
        toolName: tool.name,
        schemaVersion: deviceToolRegistry.get(tool.name)?.schemaVersion ?? 1,
        arguments: argumentsValue,
        mutation: true,
      };
    }

    const trimmedAnswer = answer.trim();
    if (trimmedAnswer.length === 0) {
      throw new ProtocolError(
        "provider_unavailable",
        "模型没有返回结果。",
        502,
      );
    }
    return { kind: "completed", answer: trimmedAnswer, usage };
  }
}

function userMessage(
  text: string,
  context: string,
  media: ProviderMedia[],
  directVideo: boolean,
): Record<string, unknown> {
  if (media.length === 0) {
    return {
      role: "user",
      content: `${text}\n\n[MINIMAL CONTEXT]\n${context}`,
    };
  }
  const videos = directVideo
    ? media.filter((item) => item.contentType.startsWith("video/"))
    : [];
  const images = videos.length > 0
    ? []
    : media.filter((item) => item.contentType.startsWith("image/"));
  const parts: Record<string, unknown>[] = [
    {
      type: "text",
      text: [
        text,
        "",
        "[MINIMAL CONTEXT]",
        context,
        "",
        videos.length > 0
          ? `附件包含 ${videos.length} 个完整视频。`
          : `附件包含 ${images.length} 张图片或视频关键帧。`,
        videos.length > 0
          ? "请依据完整视频分析，并明确无法可靠观察的部分。"
          : "只依据可见内容分析；关键帧不足以证明完整动作轨迹。",
      ].join("\n"),
    },
    ...images.map((item) => ({
      type: "image_url",
      image_url: { url: item.url },
    })),
    ...videos.map((item) => ({
      type: "video_url",
      video_url: { url: item.url },
    })),
  ];
  return { role: "user", content: parts };
}

type ProviderMediaMode = "text" | "images" | "direct_video";
type ProviderTimeoutPhase = "first_delta" | "idle" | "total";

class ProviderRequestDeadline {
  readonly controller = new AbortController();
  receivedMeaningfulDelta = false;
  private phase: ProviderTimeoutPhase = "first_delta";
  private timer: ReturnType<typeof setTimeout> | undefined;
  private readonly totalTimer: ReturnType<typeof setTimeout>;
  private readonly firstDeltaSeconds: number;

  constructor(mode: ProviderMediaMode) {
    this.firstDeltaSeconds = mode === "direct_video" ? 20 : mode === "images" ? 10 : 8;
    this.timer = this.abortAfter(this.firstDeltaSeconds, "first_delta");
    this.totalTimer = setTimeout(() => this.abort("total"), 180_000);
  }

  get signal(): AbortSignal {
    return this.controller.signal;
  }

  markMeaningfulDelta(): void {
    this.receivedMeaningfulDelta = true;
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = this.abortAfter(30, "idle");
  }

  finish(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    clearTimeout(this.totalTimer);
  }

  error(error: unknown): unknown {
    if (!this.controller.signal.aborted) return error;
    const seconds = this.phase === "first_delta" ? this.firstDeltaSeconds : this.phase === "idle" ? 30 : 180;
    return new ProtocolError(
      "provider_timeout",
      `模型请求在 ${this.phase} 阶段超过 ${seconds} 秒。`,
      504,
    );
  }

  private abortAfter(seconds: number, phase: ProviderTimeoutPhase): ReturnType<typeof setTimeout> {
    return setTimeout(() => this.abort(phase), seconds * 1_000);
  }

  private abort(phase: ProviderTimeoutPhase): void {
    this.phase = phase;
    this.controller.abort();
  }
}

export function supportsDirectVideo(model: string): boolean {
  const normalized = model.trim().toLowerCase();
  return ["qwen-vl-max", "qwen-vl-plus", "qwen2.5-vl", "qwen3-vl"]
    .some((prefix) => normalized === prefix || normalized.startsWith(`${prefix}-`));
}

function isRetryable(error: unknown): boolean {
  return !(error instanceof ProtocolError) ||
    error.code === "provider_timeout" ||
    error.code === "provider_unavailable";
}
