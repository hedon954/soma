import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentJob, ToolRequest } from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";
import type { SomaStore } from "./store.js";
import {
  type DeviceToolDefinition,
  effectiveAllowedDeviceTools,
  validateDeviceTool,
} from "./tool-registry.js";

export interface ProviderToolCall {
  toolCallID?: string;
  toolName: string;
  schemaVersion: number;
  arguments: Record<string, unknown>;
}

export type ProviderStep =
  | { kind: "completed"; answer: string; usage?: { input: number; output: number } }
  | {
      kind: "toolCalls";
      assistantText: string;
      calls: ProviderToolCall[];
      usage?: { input: number; output: number };
    };

export interface ProviderMedia {
  id: string;
  contentType: string;
  url: string;
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
    await this.store.appendEvent(job.id, lease.epoch, {
      kind: "model",
      phase: "started",
      payloadVersion: 1,
      payload: {
        provider: "managed",
        model: "configured",
        mediaMode: job.input?.mediaMode ?? "text",
        requestAttempt: job.input?.requestAttempt ?? 1,
      },
      createdAt: now,
    });
    const textItemID = randomUUID();
    let emittedText = false;
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
      const history = await this.store.events(job.id, 0, 500);
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
      const step = await this.provider.run(job, history, media, async (delta) => {
        if (delta.length === 0) return;
        emittedText = true;
        await this.store.appendEvent(job.id, lease.epoch, {
          kind: "text",
          phase: "updated",
          payloadVersion: 1,
          payload: { itemID: textItemID, delta },
          createdAt: new Date(),
        });
      });
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
          const definition = validateDeviceTool({
            name: call.toolName,
            schemaVersion: call.schemaVersion,
            arguments: call.arguments,
            allowedNames: [...activeRuntimeTools],
            ...(parameters === undefined ? {} : { parameters }),
          });
          if (job.input?.allowedRemoteTools.includes(call.toolName) === true) {
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "tool",
              phase: "started",
              payloadVersion: 1,
              payload: {
                toolCallID: call.toolCallID,
                toolName: call.toolName,
                schemaVersion: call.schemaVersion,
                arguments: call.arguments,
                mutation: false,
              },
              createdAt: now,
            });
            const result = executeRuntimeTool(
              job,
              call.toolName,
              call.arguments,
              activeRuntimeTools,
            );
            await this.store.appendEvent(job.id, lease.epoch, {
              kind: "tool",
              phase: "completed",
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
            arguments: call.arguments,
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

function executeRuntimeTool(
  job: AgentJob,
  name: string,
  argumentsValue: Record<string, unknown>,
  activeTools: Set<string>,
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
  if (name === "expand_tool_group") {
    const group = argumentsValue.tool_group;
    const groups: Record<string, string[]> = {
      records: ["mutate_user_data"],
      plans: [
        "create_training_program",
        "create_workout_template_version",
        "archive_training_program",
        "delete_training_program",
        "start_guided_workout",
      ],
      gym: ["update_gym", "switch_gym"],
      review: ["record_performance_analysis"],
      feedback: ["submit_feedback"],
    };
    const names = typeof group === "string" ? groups[group] : undefined;
    if (names === undefined) {
      return {
        ok: false,
        code: "invalid_request",
        message: "tool_group 仅支持 records、plans、gym、review、feedback。",
      };
    }
    if (names.every((tool) => activeTools.has(tool))) {
      return {
        ok: true,
        code: "ok",
        message: `工具组 ${String(group)} 已经展开。`,
      };
    }
    for (const tool of names) activeTools.add(tool);
    return {
      ok: true,
      code: "ok",
      message: `已展开工具组 ${String(group)}：${names.join(", ")}。后续步骤可使用这些工具。`,
    };
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
