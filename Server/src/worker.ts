import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentJob, ToolRequest } from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";
import type { SomaStore } from "./store-contract.js";
import { completedQuestionAnswer } from "./user-questions.js";
import {
  type DeviceToolDefinition,
  effectiveAllowedDeviceTools,
  normalizeToolArguments,
  validateDeviceTool,
} from "./tool-registry.js";

export interface ProviderToolCall {
  toolCallID?: string;
  toolName: string;
  schemaVersion: number;
  arguments: Record<string, unknown>;
}

export interface ProviderUsage {
  input?: number;
  output?: number;
  cachedInput?: number;
}

export type ProviderStep =
  | { kind: "completed"; answer: string; usage?: ProviderUsage }
  | {
      kind: "toolCalls";
      assistantText: string;
      calls: ProviderToolCall[];
      usage?: ProviderUsage;
    };

export interface ProviderMedia {
  id: string;
  contentType: string;
  url: string;
  byteLength?: number;
}

export interface JobMediaResolver {
  resolve(job: AgentJob): Promise<ProviderMedia[]>;
}

export interface ManagedModelProvider {
  run(
    job: AgentJob,
    events: AgentEvent[],
    media: ProviderMedia[],
    onTextDelta?: (delta: string) => Promise<void>,
    onReasoningDelta?: (delta: string) => Promise<void>,
    onVideoFallback?: (frameCount: number) => Promise<void>,
  ): Promise<ProviderStep>;
}

export class DeterministicTestProvider implements ManagedModelProvider {
  constructor(private readonly step: ProviderStep = {
    kind: "completed",
    answer: "远程任务已完成。",
  }) {}

  async run(
    _job: AgentJob,
    _events: AgentEvent[],
    _media: ProviderMedia[],
    onTextDelta?: (delta: string) => Promise<void>,
    _onReasoningDelta?: (delta: string) => Promise<void>,
  ): Promise<ProviderStep> {
    if (this.step.kind === "completed" && onTextDelta !== undefined) {
      await onTextDelta(this.step.answer);
    }
    return structuredClone(this.step);
  }
}

export class AgentWorker {
  constructor(
    private readonly store: SomaStore,
    private readonly provider: ManagedModelProvider,
    private readonly owner = `worker-${randomUUID()}`,
    private readonly leaseSeconds = 30,
    private readonly mediaResolver: JobMediaResolver = {
      async resolve() {
        return [];
      },
    },
  ) {}

  async runOnce(now = new Date()): Promise<AgentJob | undefined> {
    const lease = await this.store.claimJob(
      this.owner,
      now,
      this.leaseSeconds,
    );
    if (lease === undefined) return undefined;
    const job = lease.job;
    if (isTerminal(job.state)) return job;
    const history = await this.store.events(job.id, 0, 500);
    const questionAnswer = completedQuestionAnswer(history);
    if (questionAnswer !== undefined) {
      await this.store.appendEvent(job.id, lease.epoch, {
        kind: "output", phase: "completed", payloadVersion: 1,
        payload: { answer: questionAnswer }, createdAt: now,
      });
      return this.store.transition(job.id, "completed", now, lease.epoch);
    }
    const exposedToolNames = effectiveAllowedDeviceTools(
      job.input?.modelInput.activeTools ?? [],
      history,
    );
    history.push(await this.store.appendEvent(job.id, lease.epoch, {
      kind: "model",
      phase: "started",
      payloadVersion: 1,
      payload: {
        provider: "managed",
        model: "configured",
        mediaMode: job.input?.mediaMode ?? "text",
        requestAttempt: job.input?.requestAttempt ?? 1,
        exposedToolNames,
        exposedToolCount: exposedToolNames.length,
      },
      createdAt: now,
    }));
    const textItemID = randomUUID();
    const reasoningItemID = randomUUID();
    let emittedText = false;
    let emittedReasoning = false;
    let completedReasoning = false;
    let reasoningText = "";
    const heartbeat = setInterval(() => {
      void this.store.renewLease(
        job.id,
        lease.owner,
        lease.epoch,
        new Date(),
        this.leaseSeconds,
      );
    }, Math.max(1_000, Math.floor(this.leaseSeconds * 1_000 / 3)));
    try {
      const completedOperations = history.filter((event) =>
        event.kind === "tool" && event.phase === "completed"
      ).length;
      const maximumOperations = job.input?.modelInput.runtime.maxSteps ?? 1;
      if (completedOperations >= maximumOperations) {
        throw new ProtocolError(
          "provider_unavailable",
          "Agent 已达到模型输入指定的 ReAct 步数上限。",
          409,
        );
      }
      const media = await this.mediaResolver.resolve(job);
      const step = await this.provider.run(
        job,
        history,
        media,
        async (delta) => {
          if (delta.length === 0) return;
          emittedText = true;
          await this.store.appendEvent(job.id, lease.epoch, {
            kind: "text",
            phase: "updated",
            payloadVersion: 1,
            payload: { itemID: textItemID, delta },
            createdAt: new Date(),
          });
        },
        async (delta) => {
          if (delta.length === 0) return;
          if (!emittedReasoning) {
            emittedReasoning = true;
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "reasoning",
              phase: "started",
              payloadVersion: 1,
              payload: { itemID: reasoningItemID },
              createdAt: new Date(),
            });
          }
          reasoningText += delta;
          await this.store.appendEvent(job.id, lease.epoch, {
            kind: "reasoning",
            phase: "updated",
            payloadVersion: 1,
            payload: { itemID: reasoningItemID, delta },
            createdAt: new Date(),
          });
        },
        async (frameCount) => {
          await this.store.appendEvent(job.id, lease.epoch, {
            kind: "model", phase: "updated", payloadVersion: 1,
            payload: { mediaMode: "keyframes", fallbackReason: "video_input_unsupported", frameCount },
            createdAt: new Date(),
          });
        },
      );
      if (emittedReasoning) {
        await this.store.appendEvent(job.id, lease.epoch, {
          kind: "reasoning",
          phase: "completed",
          payloadVersion: 1,
          payload: { itemID: reasoningItemID, text: reasoningText },
          createdAt: new Date(),
        });
        completedReasoning = true;
      }
      if (emittedText) {
        await this.store.appendEvent(job.id, lease.epoch, {
          kind: "text",
          phase: "completed",
          payloadVersion: 1,
          payload: { itemID: textItemID },
          createdAt: new Date(),
        });
      }
      if (step.kind === "toolCalls") {
        if (step.calls.length > maximumOperations - completedOperations) {
          throw new ProtocolError(
            "provider_unavailable",
            "Agent 返回的 Tool 批次超过模型输入指定的 ReAct 步数上限。",
            409,
          );
        }
        const calls = step.calls.map((call) => ({
          ...call,
          toolCallID: call.toolCallID ?? randomUUID(),
        }));
        await this.store.appendEvent(job.id, lease.epoch, {
          kind: "model",
          phase: "completed",
          payloadVersion: 1,
          payload: {
            assistantText: step.assistantText,
            ...(reasoningText.length === 0 ? {} : { reasoningText }),
            toolCalls: calls.map((call) => ({
              id: call.toolCallID,
              type: "function",
              function: {
                name: call.toolName,
                arguments: JSON.stringify(call.arguments),
              },
            })),
            ...(step.usage === undefined ? {} : { usage: step.usage }),
          },
          createdAt: now,
        });
        const deviceRequests: Omit<ToolRequest, "id">[] = [];
        const activeRuntimeTools = new Set(effectiveAllowedDeviceTools(
          job.input?.modelInput.activeTools ?? [],
          history,
        ));
        for (const call of calls) {
          const submittedTool = job.input?.modelInput.tools.find(
            (tool) => tool.name === call.toolName,
          );
          if (
            submittedTool === undefined ||
            submittedTool.schemaVersion !== call.schemaVersion
          ) {
            throw new ProtocolError(
              "tool_schema_unsupported",
              "Tool Schema 与模型输入契约不一致。",
              409,
            );
          }
          const parameters = submittedToolParameters(job, call.toolName);
          const normalizedArguments = parameters === undefined
            ? call.arguments
            : normalizeToolArguments(call.arguments, parameters);
          await this.store.appendEvent(job.id, lease.epoch, {
            kind: "tool",
            phase: "started",
            payloadVersion: 1,
            payload: {
              toolCallID: call.toolCallID,
              toolName: call.toolName,
              schemaVersion: call.schemaVersion,
              arguments: normalizedArguments,
            },
            createdAt: now,
          });
          let definition: DeviceToolDefinition;
          try {
            definition = validateDeviceTool({
              name: call.toolName,
              schemaVersion: call.schemaVersion,
              arguments: normalizedArguments,
              allowedNames: [...activeRuntimeTools],
              ...(parameters === undefined ? {} : { parameters }),
            });
          } catch (error) {
            if (!isRetryableToolArgumentError(error)) throw error;
            const result = {
              ok: false,
              code: "invalid_tool_arguments",
              message: `${error.message} 请按已注册 Schema 修正后重新调用同一工具。`,
              field: call.toolName,
              expected:
                "数值字段使用 JSON number；自然语言分数先换算成小数；其余字段满足严格 Schema",
              retryable: true,
            };
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "tool",
              phase: "failed",
              payloadVersion: 1,
              payload: {
                toolCallID: call.toolCallID,
                toolName: call.toolName,
                schemaVersion: call.schemaVersion,
                arguments: call.arguments,
                result,
              },
              createdAt: now,
            });
            continue;
          }
          if (job.input?.allowedRemoteTools.includes(call.toolName) === true) {
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "tool",
              phase: "updated",
              payloadVersion: 1,
              payload: {
                toolCallID: call.toolCallID,
                toolName: call.toolName,
                schemaVersion: call.schemaVersion,
                arguments: normalizedArguments,
                mutation: false,
              },
              createdAt: now,
            });
            const result = executeRuntimeTool(
              job,
              call.toolName,
              normalizedArguments,
            );
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "tool",
              phase: "completed",
              payloadVersion: 1,
              payload: {
                toolCallID: call.toolCallID,
                toolName: call.toolName,
                schemaVersion: call.schemaVersion,
                arguments: normalizedArguments,
                result,
              },
              createdAt: now,
            });
            continue;
          }
          const submittedSchema = job.input?.allowedDeviceToolSchemas?.find(
            (item) => item.name === call.toolName,
          );
          if (
            submittedSchema === undefined ||
            submittedSchema.schemaVersion !== call.schemaVersion
          ) {
            throw new ProtocolError(
              "tool_schema_unsupported",
              "Tool Schema 与任务提交契约不一致。",
              409,
            );
          }
          deviceRequests.push({
            jobID: job.id,
            toolCallID: call.toolCallID,
            toolName: call.toolName,
            schemaVersion: call.schemaVersion,
            arguments: normalizedArguments,
            mutation: definition.mutation,
            expiresAt: new Date(now.getTime() + 24 * 60 * 60 * 1_000),
          });
        }
        for (const request of deviceRequests) {
          await this.store.saveToolRequest(request, now, lease.epoch);
        }
        if (deviceRequests.length === 0) {
          return await this.store.transition(job.id, "queued", now, lease.epoch);
        }
        return this.store.getJob(job.deviceID, job.id);
      }
      await this.store.appendEvent(job.id, lease.epoch, {
        kind: "output",
        phase: "completed",
        payloadVersion: 1,
        payload: {
          answer: step.answer,
          ...(step.usage === undefined ? {} : { usage: step.usage }),
        },
        createdAt: now,
      });
      return await this.store.transition(
        job.id,
        "completed",
        now,
        lease.epoch,
      );
    } catch (error) {
      const latest = await this.store.getJob(job.deviceID, job.id);
      if (latest !== undefined && isTerminal(latest.state)) {
        return latest;
      }
      const code =
        error instanceof ProtocolError
          ? error.code
          : "provider_unavailable";
      try {
        if (emittedReasoning && !completedReasoning) {
          await this.store.appendEvent(job.id, lease.epoch, {
            kind: "reasoning",
            phase: "failed",
            payloadVersion: 1,
            payload: { itemID: reasoningItemID, text: reasoningText },
            createdAt: new Date(),
          });
        }
        await this.store.appendEvent(job.id, lease.epoch, {
          kind: "error",
          phase: "failed",
          payloadVersion: 1,
          payload: {
            code,
            mediaMode: job.input?.mediaMode ?? "text",
            requestAttempt: job.input?.requestAttempt ?? 1,
          },
          createdAt: now,
        });
        return await this.store.transition(
          job.id,
          "failed",
          now,
          lease.epoch,
          code,
        );
      } catch {
        return await this.store.getJob(job.deviceID, job.id);
      }
    } finally {
      clearInterval(heartbeat);
    }
  }
}

function isRetryableToolArgumentError(error: unknown): error is ProtocolError {
  return error instanceof ProtocolError &&
    error.message.startsWith("Tool 参数不符合固定 Schema：");
}

function executeRuntimeTool(
  job: AgentJob,
  name: string,
  argumentsValue: Record<string, unknown>,
): Record<string, unknown> {
  if (job.input === undefined) {
    return { ok: false, code: "invalid_request", message: "任务内容已清理。" };
  }
  if (name === "load_skill") {
    const skillID = argumentsValue.skill_id;
    if (typeof skillID !== "string" || skillID.trim().length === 0) {
      return {
        ok: false,
        code: "invalid_request",
        message: "load_skill 缺少 skill_id。",
      };
    }
    const normalizedID = skillID.trim();
    const skill = job.input.modelInput.skills.find(
      (item) => item.id === normalizedID,
    );
    return skill === undefined
      ? {
          ok: false,
          code: "invalid_request",
          message: `未知 Skill：${normalizedID}。可用 ID：${job.input.modelInput.skills.map((item) => item.id).join("、")}。`,
        }
      : { ok: true, code: "ok", message: skill.content };
  }
  throw new ProtocolError(
    "tool_schema_unsupported",
    "远程运行时 Tool 不在固定契约内。",
    409,
  );
}

function submittedToolParameters(
  job: AgentJob,
  name: string,
): DeviceToolDefinition["parameters"] | undefined {
  const definition = job.input?.modelInput.tools.find(
    (tool) => tool.name === name,
  )?.definition;
  const functionValue = definition?.function;
  if (
    functionValue === null ||
    typeof functionValue !== "object" ||
    Array.isArray(functionValue)
  ) {
    return undefined;
  }
  const parameters = (functionValue as Record<string, unknown>).parameters;
  if (
    parameters === null ||
    typeof parameters !== "object" ||
    Array.isArray(parameters)
  ) {
    return undefined;
  }
  return parameters as DeviceToolDefinition["parameters"];
}
