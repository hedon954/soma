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
import { deviceToolRegistry } from "./tool-registry.js";

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
  ): Promise<ProviderStep> {
    if (job.input === undefined) {
      throw new ProtocolError("job_expired", "任务内容已清理。", 410);
    }
    const messages: Record<string, unknown>[] = [
      {
        role: "system",
        content:
          "你是 Soma 的远程执行 Agent。只依据当前任务最小上下文工作；需要设备数据或写入时调用允许的固定设备 Tool。不要输出思维过程。",
      },
      userMessage(job.input.text, job.input.contextSnapshot, media),
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
    const tools = job.input.allowedDeviceTools.flatMap((name) => {
      const definition = deviceToolRegistry.get(name);
      return definition === undefined
        ? []
        : [{
            type: "function",
            function: {
              name,
              description:
                "由用户设备执行的 Soma 固定 Tool；只传当前任务明确需要的最小参数。",
              parameters: definition.parameters,
            },
          }];
    });
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
          stream: false,
        }),
      },
    );
    if (!response.ok) {
      throw new ProtocolError(
        "provider_unavailable",
        "模型服务暂时不可用。",
        503,
      );
    }
    const payload = (await response.json()) as ChatCompletionResponse;
    const message = payload.choices?.[0]?.message;
    const tool = message?.tool_calls?.[0]?.function;
    if (tool?.name !== undefined) {
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
        schemaVersion: 1,
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
    return {
      kind: "completed",
      answer,
      usage: {
        input: payload.usage?.prompt_tokens ?? 0,
        output: payload.usage?.completion_tokens ?? 0,
      },
    };
  }
}

function userMessage(
  text: string,
  context: string,
  media: ProviderMedia[],
): Record<string, unknown> {
  if (media.length === 0) {
    return {
      role: "user",
      content: `${text}\n\n[MINIMAL CONTEXT]\n${context}`,
    };
  }
  const images = media.filter((item) => item.contentType.startsWith("image/"));
  const parts: Record<string, unknown>[] = [
    {
      type: "text",
      text: [
        text,
        "",
        "[MINIMAL CONTEXT]",
        context,
        "",
        `附件包含 ${images.length} 张图片或视频关键帧。`,
        "只依据可见内容分析；关键帧不足以证明完整动作轨迹。",
      ].join("\n"),
    },
    ...images.map((item) => ({
      type: "image_url",
      image_url: { url: item.url },
    })),
  ];
  return { role: "user", content: parts };
}
