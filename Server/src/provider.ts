import type {
  AgentEvent,
  AgentJob,
  AgentModelMessage,
} from "./domain.js";
import { ProtocolError } from "./domain.js";
import type {
  ManagedModelProvider,
  ProviderMedia,
  ProviderStep,
  ProviderToolCall,
} from "./worker.js";
import { effectiveAllowedDeviceTools } from "./tool-registry.js";

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
    const hasCompletedModelStep = events.some((event) =>
      event.kind === "model" && event.phase === "completed"
    );
    const messages = modelMessages(
      job.input.modelInput.messages,
      media,
      directVideo,
      hasCompletedModelStep,
    );
    for (const event of events) {
      if (
        event.kind === "model" &&
        event.phase === "completed" &&
        Array.isArray(event.payload.toolCalls)
      ) {
        const toolCalls = event.payload.toolCalls as {
          id?: unknown;
          type?: unknown;
          function?: unknown;
        }[];
        messages.push({
          role: "assistant",
          content: typeof event.payload.assistantText === "string"
            ? event.payload.assistantText
            : null,
          tool_calls: toolCalls,
        });
        for (const call of toolCalls) {
          if (typeof call.id !== "string") continue;
          const result = events.find((candidate) =>
            candidate.kind === "tool" &&
            candidate.phase === "completed" &&
            candidate.payload.toolCallID === call.id
          );
          if (result !== undefined) {
            messages.push({
              role: "tool",
              tool_call_id: call.id,
              content: JSON.stringify(result.payload.result ?? {}),
            });
          }
        }
      }
    }
    const activeTools = effectiveAllowedDeviceTools(
      job.input.modelInput.activeTools,
      events,
    );
    const toolsByName = new Map(
      job.input.modelInput.tools.map((tool) => [tool.name, tool]),
    );
    const tools = activeTools.flatMap((name) => {
      const tool = toolsByName.get(name);
      return tool === undefined ? [] : [tool.definition];
    });
    const toolSchemas = new Map(
      activeTools.flatMap((name) => {
        const tool = toolsByName.get(name);
        return tool === undefined ? [] : [[name, tool.schemaVersion] as const];
      }),
    );
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
      const deadline = new ProviderRequestDeadline(
        mediaMode,
        job.input.modelInput.runtime.deadlines,
        !hasCompletedModelStep,
      );
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
              tool_choice: job.input.modelInput.runtime.toolChoice,
              parallel_tool_calls:
                job.input.modelInput.runtime.parallelToolCalls,
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
            toolSchemas,
          );
        } else {
          step = await this.consumeResponse(
            response,
            onTextDelta,
            deadline,
            toolSchemas,
          );
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
    toolSchemas: Map<string, number>,
  ): Promise<ProviderStep> {
    const payload = (await response.json()) as ChatCompletionResponse;
    const message = payload.choices?.[0]?.message;
    if ((message?.tool_calls?.length ?? 0) > 0) {
      deadline.markMeaningfulDelta();
      return {
        kind: "toolCalls",
        assistantText: message?.content ?? "",
        calls: parseResponseToolCalls(message?.tool_calls ?? [], toolSchemas),
        usage: {
          input: payload.usage?.prompt_tokens ?? 0,
          output: payload.usage?.completion_tokens ?? 0,
        },
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
    toolSchemas: Map<string, number> = new Map(),
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

    const orderedTools = [...toolCalls.entries()]
      .sort(([lhs], [rhs]) => lhs - rhs)
      .map(([, value]) => value)
      .filter((tool) => tool.name.length > 0);
    if (orderedTools.length > 0) {
      return {
        kind: "toolCalls",
        assistantText: answer,
        calls: parseResponseToolCalls(
          orderedTools.map((tool) => ({
            ...(tool.id === undefined ? {} : { id: tool.id }),
            function: { name: tool.name, arguments: tool.arguments },
          })),
          toolSchemas,
        ),
        usage,
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

function modelMessages(
  input: AgentModelMessage[],
  media: ProviderMedia[],
  directVideo: boolean,
  clearHistoricalMedia: boolean,
): Record<string, unknown>[] {
  const mediaByID = new Map(media.map((item) => [item.id, item]));
  return input.map((message, index) => {
    const attachments = message.mediaIDs
      .map((id) => mediaByID.get(id))
      .filter((item): item is ProviderMedia => item !== undefined);
    if (
      attachments.length === 0 ||
      (clearHistoricalMedia && index > 0 && index < input.length - 1)
    ) {
      const text = attachments.length > 0
        ? `${message.text}\n（历史视觉帧已在后续步骤清除，仅保留文字上下文。）`
        : message.text;
      return { role: message.role, content: text };
    }
    return {
      role: message.role,
      content: [
        { type: "text", text: message.text },
        ...attachments.map((item) => {
          if (directVideo && item.contentType.startsWith("video/")) {
            return {
              type: "video_url",
              video_url: { url: item.url, fps: 2 },
            };
          }
          return {
            type: "image_url",
            image_url: { url: item.url, detail: "auto" },
          };
        }),
      ],
    };
  });
}

function parseResponseToolCalls(
  values: {
    id?: string;
    function?: { name?: string; arguments?: string };
  }[],
  schemas: Map<string, number>,
): ProviderToolCall[] {
  return values.map((value) => {
    const name = value.function?.name;
    if (name === undefined || !schemas.has(name)) {
      throw new ProtocolError(
        "tool_schema_unsupported",
        "Provider 返回了未暴露的 Tool。",
        409,
      );
    }
    let argumentsValue: Record<string, unknown>;
    try {
      argumentsValue = JSON.parse(value.function?.arguments ?? "{}") as Record<
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
      ...(value.id === undefined ? {} : { toolCallID: value.id }),
      toolName: name,
      schemaVersion: schemas.get(name) ?? 1,
      arguments: argumentsValue,
    };
  });
}

type ProviderMediaMode = "text" | "images" | "direct_video";
type ProviderTimeoutPhase = "first_delta" | "total";

class ProviderRequestDeadline {
  readonly controller = new AbortController();
  receivedMeaningfulDelta = false;
  private phase: ProviderTimeoutPhase = "first_delta";
  private timer: ReturnType<typeof setTimeout> | undefined;
  private readonly totalTimer: ReturnType<typeof setTimeout>;
  private readonly firstDeltaSeconds: number;
  private readonly totalSeconds: number;

  constructor(
    mode: ProviderMediaMode,
    policy: NonNullable<AgentJob["input"]>["modelInput"]["runtime"]["deadlines"],
    enforceFirstDelta: boolean,
  ) {
    this.firstDeltaSeconds = mode === "direct_video"
      ? policy.directVideoTTFT
      : mode === "images"
        ? policy.imageTTFT
        : policy.textTTFT;
    this.timer = enforceFirstDelta
      ? this.abortAfter(this.firstDeltaSeconds, "first_delta")
      : undefined;
    this.totalSeconds = mode === "direct_video"
      ? policy.videoLoopTotal
      : mode === "images"
        ? policy.imageLoopTotal
        : policy.textLoopTotal;
    this.totalTimer = setTimeout(
      () => this.abort("total"),
      this.totalSeconds * 1_000,
    );
  }

  get signal(): AbortSignal {
    return this.controller.signal;
  }

  markMeaningfulDelta(): void {
    this.receivedMeaningfulDelta = true;
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
  }

  finish(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    clearTimeout(this.totalTimer);
  }

  error(error: unknown): unknown {
    if (!this.controller.signal.aborted) return error;
    const seconds = this.phase === "first_delta"
      ? this.firstDeltaSeconds
      : this.totalSeconds;
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
