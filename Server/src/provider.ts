import { providerFailure } from "./provider-failure.js";
import { boundedProviderError, checkedFallbackMedia, explicitlyRejectsVideo,
  frameFallbackPrompt, parseVideoFallbacks, type VideoFrameFallback } from "./video-fallback.js";
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
      reasoning_content?: string | null;
      reasoning?: string | null;
      analysis?: string | null;
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
      reasoning_content?: string | null;
      reasoning?: string | null;
      analysis?: string | null;
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

export const modelStepRetryDelaysSeconds = [1, 2, 4] as const;

type ModelStepRetrySleeper = (seconds: number) => Promise<void>;

export class OpenAICompatibleManagedProvider implements ManagedModelProvider {
  constructor(
    private readonly baseURL: string,
    private readonly apiKey: string,
    private readonly model: string,
    private readonly fetcher: typeof fetch = fetch,
    private readonly retrySleeper: ModelStepRetrySleeper = async (seconds) => {
      await new Promise((resolve) => setTimeout(resolve, seconds * 1_000));
    },
    private readonly directVideoEnabled: boolean = false,
    private readonly extraConfig?: Record<string, unknown>,
  ) {}

  async run(
    job: AgentJob,
    events: AgentEvent[],
    media: ProviderMedia[],
    onTextDelta?: (delta: string) => Promise<void>,
    onReasoningDelta?: (delta: string) => Promise<void>,
    onVideoFallback?: (frameCount: number) => Promise<void>,
  ): Promise<ProviderStep> {
    if (job.input === undefined) {
      throw new ProtocolError("job_expired", "任务内容已清理。", 410);
    }
    const manifests = parseVideoFallbacks(job.input.modelInput.videoFallbacks, job.input.modelInput.messages);
    const directVideo = this.directVideoEnabled;
    const hasCompletedModelStep = events.some((event) => event.kind === "model" && event.phase === "completed");
    const referencedIDs = new Set(job.input.modelInput.messages.flatMap((message) => message.mediaIDs));
    if ([...referencedIDs].some((id) => !media.some((item) => item.id === id))) {
      throw new ProtocolError("video_fallback_unavailable", "任务引用的媒体已不可用。请重新发送附件。", 422);
    }
    const videoIDs = media.filter((item) => referencedIDs.has(item.id) && item.contentType.startsWith("video/")).map((item) => item.id);
    const hasVideo = videoIDs.length > 0;
    const persistedFallback = events.some((event) => event.kind === "model" &&
      event.phase === "updated" && event.payload.fallbackReason === "video_input_unsupported");
    let useFrames = persistedFallback || job.input.mediaMode === "keyframes" || (!directVideo && hasVideo);
    let fallbackMap = new Map<string, VideoFrameFallback>();
    if (useFrames) {
      fallbackMap = checkedFallbackMedia(manifests, media, videoIDs);
      if (!persistedFallback) await onVideoFallback?.(manifests.reduce((sum, item) => sum + item.frameIDs.length, 0));
    }
    let usesDirectVideo = directVideo && hasVideo && !useFrames;
    const appendCompletedModelEvents = (
      messages: Record<string, unknown>[],
    ): void => {
      let reasoningSinceModelStart: string | undefined;
      for (const event of events) {
        if (event.kind === "model" && event.phase === "started") {
          reasoningSinceModelStart = undefined;
          continue;
        }
        if (event.kind === "reasoning" && event.phase === "completed") {
          const text = event.payload.text;
          reasoningSinceModelStart = typeof text === "string" && text.length > 0
            ? text
            : undefined;
          continue;
        }
        if (
          event.kind !== "model" ||
          event.phase !== "completed" ||
          !Array.isArray(event.payload.toolCalls)
        ) {
          continue;
        }
        const toolCalls = event.payload.toolCalls as {
          id?: unknown;
          type?: unknown;
          function?: unknown;
        }[];
        const explicitReasoning = event.payload.reasoningText;
        const reasoning = typeof explicitReasoning === "string" &&
            explicitReasoning.length > 0
          ? explicitReasoning
          : reasoningSinceModelStart;
        const assistantMessage: Record<string, unknown> = {
          role: "assistant",
          content: typeof event.payload.assistantText === "string"
            ? event.payload.assistantText
            : null,
          tool_calls: toolCalls,
        };
        if (reasoning !== undefined) {
          assistantMessage.reasoning_content = reasoning;
        }
        messages.push(assistantMessage);
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
        reasoningSinceModelStart = undefined;
      }
    };
    let messages = modelMessages(
      job.input.modelInput.messages,
      media,
      usesDirectVideo,
      hasCompletedModelStep,
      fallbackMap,
    );
    appendCompletedModelEvents(messages);
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
    const hasImages = media.some((item) =>
      referencedIDs.has(item.id) && item.contentType.startsWith("image/")
    );
    const maximumRequestAttempts = modelStepRetryDelaysSeconds.length + 1;
    let lastError: unknown;
    for (let attempt = 1; attempt <= maximumRequestAttempts; attempt += 1) {
      const mediaMode = useFrames
        ? "keyframes"
        : usesDirectVideo
        ? "direct_video"
        : hasImages
          ? "images"
          : "text";
      const deadline = new ProviderRequestDeadline(
        mediaMode,
        job.input.modelInput.runtime.deadlines,
        !hasCompletedModelStep,
      );
      try {
        const requestBody = mergeProviderExtraConfig(
          {
            model: this.model,
            messages,
            tools,
            tool_choice: job.input.modelInput.runtime.toolChoice,
            parallel_tool_calls:
              job.input.modelInput.runtime.parallelToolCalls,
            stream: true,
            stream_options: { include_usage: true },
          },
          this.extraConfig ?? defaultProviderExtraConfig(
            this.baseURL,
            this.model,
          ),
        );
        const response = await this.fetcher(
          `${this.baseURL.replace(/\/$/, "")}/chat/completions`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${this.apiKey}`,
              "content-type": "application/json",
            },
            body: JSON.stringify(requestBody),
            signal: deadline.signal,
          },
        );
        if (!response.ok) {
          const description = await boundedProviderError(response);
          if (usesDirectVideo && !useFrames && explicitlyRejectsVideo(response.status, description)) {
            fallbackMap = checkedFallbackMedia(manifests, media, videoIDs);
            usesDirectVideo = false;
            useFrames = true;
            messages = modelMessages(job.input.modelInput.messages, media, false, hasCompletedModelStep, fallbackMap);
            appendCompletedModelEvents(messages);
            deadline.finish();
            await onVideoFallback?.(manifests.reduce((sum, item) => sum + item.frameIDs.length, 0));
            attempt -= 1;
            continue;
          }
          throw providerFailure(response.status, description);
        }
        let step: ProviderStep;
        if (response.headers.get("content-type")?.includes("text/event-stream")) {
          step = await this.consumeStream(
            response,
            onTextDelta,
            onReasoningDelta,
            () => deadline.markMeaningfulDelta(),
            toolSchemas,
          );
        } else {
          step = await this.consumeResponse(
            response,
            onTextDelta,
            onReasoningDelta,
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
          const retryDelay = modelStepRetryDelaysSeconds[attempt - 1];
          if (retryDelay === undefined) throw lastError;
          await this.retrySleeper(retryDelay);
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
    onReasoningDelta: ((delta: string) => Promise<void>) | undefined,
    deadline: ProviderRequestDeadline,
    toolSchemas: Map<string, number>,
  ): Promise<ProviderStep> {
    const payload = (await response.json()) as ChatCompletionResponse;
    const message = payload.choices?.[0]?.message;
    const reasoning = reasoningText(message);
    if (reasoning !== undefined) {
      deadline.markMeaningfulDelta();
      await onReasoningDelta?.(reasoning);
    }
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
    onReasoningDelta?: (delta: string) => Promise<void>,
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
    let reasoningEmission = Promise.resolve();
    const deliverReasoning = (text: string): Promise<void> => {
      if (onReasoningDelta === undefined || text.length === 0) {
        return reasoningEmission;
      }
      reasoningEmission = reasoningEmission.then(() => onReasoningDelta(text));
      return reasoningEmission;
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
      const reasoning = reasoningText(delta);
      if (reasoning !== undefined) {
        onMeaningfulDelta?.();
        await deliverReasoning(reasoning);
      }
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
    await reasoningEmission;

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

function reasoningText(
  value:
    | {
      reasoning_content?: string | null;
      reasoning?: string | null;
      analysis?: string | null;
    }
    | undefined,
): string | undefined {
  for (const candidate of [
    value?.reasoning_content,
    value?.reasoning,
    value?.analysis,
  ]) {
    if (typeof candidate === "string" && candidate.length > 0) {
      return candidate;
    }
  }
  return undefined;
}

const providerReservedExtraConfigKeys = new Set([
  "messages",
  "stream",
  "stream_options",
]);

export function defaultProviderExtraConfig(
  baseURL: string,
  model: string,
): Record<string, unknown> {
  const endpoint = baseURL.toLowerCase();
  const modelID = model.toLowerCase();
  if (
    endpoint.includes("api.openai.com") ||
    endpoint.includes("generativelanguage.googleapis.com")
  ) return {};
  if (
    endpoint.includes("dashscope") ||
    endpoint.includes("bailian") ||
    endpoint.includes("aliyun") ||
    endpoint.includes("alibaba") ||
    endpoint.includes("siliconflow") ||
    endpoint.includes("idealab")
  ) return { enable_thinking: false };
  if (endpoint.includes("openrouter")) {
    return { reasoning: { enabled: false } };
  }
  if (
    endpoint.includes("deepseek") ||
    endpoint.includes("bigmodel") ||
    endpoint.includes("zhipu") ||
    endpoint.includes("volces") ||
    endpoint.includes("volcengine")
  ) return { thinking: { type: "disabled" } };
  if (modelID.includes("qwen") || modelID.includes("qwq")) {
    return { chat_template_kwargs: { enable_thinking: false } };
  }
  if (
    modelID.includes("glm") ||
    modelID.includes("chatglm") ||
    modelID.includes("deepseek")
  ) return { thinking: { type: "disabled" } };
  return {};
}

export function parseProviderExtraConfig(
  raw: string | undefined,
): Record<string, unknown> | undefined {
  if (raw === undefined || raw.trim().length === 0) return undefined;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error("SOMA_PROVIDER_EXTRA_CONFIG 必须是合法 JSON 对象。");
  }
  if (value === null || Array.isArray(value) || typeof value !== "object") {
    throw new Error("SOMA_PROVIDER_EXTRA_CONFIG 必须是 JSON 对象。");
  }
  const dictionary = value as Record<string, unknown>;
  const reserved = Object.keys(dictionary).filter((key) =>
    providerReservedExtraConfigKeys.has(key)
  );
  if (reserved.length > 0) {
    throw new Error(`SOMA_PROVIDER_EXTRA_CONFIG 不能包含 ${reserved.join(", ")}。`);
  }
  return dictionary;
}

function mergeProviderExtraConfig(
  base: Record<string, unknown>,
  overlay: Record<string, unknown>,
): Record<string, unknown> {
  const result = { ...base };
  for (const [key, value] of Object.entries(overlay)) {
    if (providerReservedExtraConfigKeys.has(key)) continue;
    const existing = result[key];
    if (
      value !== null && typeof value === "object" && !Array.isArray(value) &&
      existing !== null && typeof existing === "object" &&
      !Array.isArray(existing)
    ) {
      result[key] = mergeProviderExtraConfig(
        existing as Record<string, unknown>,
        value as Record<string, unknown>,
      );
    } else {
      result[key] = value;
    }
  }
  return result;
}

function modelMessages(
  input: AgentModelMessage[],
  media: ProviderMedia[],
  directVideo: boolean,
  clearHistoricalMedia: boolean,
  fallbackMap: Map<string, VideoFrameFallback> = new Map(),
): Record<string, unknown>[] {
  const mediaByID = new Map(media.map((item) => [item.id, item]));
  return input.map((message, index) => {
    const clearImages = clearHistoricalMedia && index > 0 && index < input.length - 1;
    const frameIDs = new Set([...fallbackMap.values()].flatMap((value) => value.frameIDs));
    const messageFallbacks = message.mediaIDs.flatMap((id) => {
      const value = fallbackMap.get(id);
      return value === undefined ? [] : [value];
    });
    const text = [message.text, ...messageFallbacks.map(frameFallbackPrompt)].join("\n");
    const attachments = message.mediaIDs
      .flatMap((id) => fallbackMap.get(id)?.frameIDs ?? [id])
      .map((id) => ({ id, item: mediaByID.get(id) }))
      .filter((entry): entry is { id: string; item: ProviderMedia } =>
        entry.item !== undefined
      )
      .filter((entry) => directVideo
        ? !entry.id.startsWith("current-video-frame-")
        : !entry.item.contentType.startsWith("video/"))
      .filter((entry) => !clearImages || frameIDs.has(entry.id) || entry.item.contentType.startsWith("video/"))
      .map((entry) => entry.item);
    if (attachments.length === 0) {
      const text = clearImages && message.mediaIDs.length > 0
        ? `${message.text}\n（历史图片已在后续步骤清除，仅保留文字上下文。）`
        : message.text;
      return { role: message.role, content: text };
    }
    return {
      role: message.role,
      content: [
        { type: "text", text },
        ...attachments.map((item) => {
          if (directVideo && item.contentType.startsWith("video/")) {
            return {
              type: "video_url",
              video_url: { url: item.url },
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

type ProviderMediaMode = "text" | "images" | "keyframes" | "direct_video";
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

export function explicitCapabilityFlag(value: string | undefined): boolean {
  return value?.trim().toLowerCase() === "true";
}

function isRetryable(error: unknown): boolean {
  if (error instanceof ProtocolError) {
    return error.code === "provider_timeout" || error.code === "provider_rate_limited" ||
      (
        error.code === "provider_unavailable" &&
        (
          [408, 409, 425, 429].includes(error.status) ||
          error.status >= 500
        )
      );
  }
  return error instanceof TypeError;
}
