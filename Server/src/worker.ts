import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentJob, ToolRequest } from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";
import type { SomaStore } from "./store.js";
import {
  effectiveAllowedDeviceTools,
  validateDeviceTool,
} from "./tool-registry.js";

export type ProviderStep =
  | { kind: "completed"; answer: string; usage?: { input: number; output: number } }
  | {
      kind: "deviceTool";
      toolCallID?: string;
      toolName: string;
      schemaVersion: number;
      arguments: Record<string, unknown>;
      mutation: boolean;
    };

export interface ProviderMedia {
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
      if (step.kind === "deviceTool") {
        const submittedSchema = job.input?.allowedDeviceToolSchemas?.find(
          (item) => item.name === step.toolName,
        );
        if (
          submittedSchema !== undefined &&
          submittedSchema.schemaVersion !== step.schemaVersion
        ) {
          throw new ProtocolError(
            "tool_schema_unsupported",
            "Tool Schema 与任务提交契约不一致。",
            409,
          );
        }
        const definition = validateDeviceTool({
          name: step.toolName,
          schemaVersion: step.schemaVersion,
          arguments: step.arguments,
          allowedNames: effectiveAllowedDeviceTools(
            job.input?.allowedDeviceTools ?? [],
            history,
          ),
        });
        const request: Omit<ToolRequest, "id"> = {
          jobID: job.id,
          toolCallID: step.toolCallID ?? randomUUID(),
          toolName: step.toolName,
          schemaVersion: step.schemaVersion,
          arguments: step.arguments,
          mutation: definition.mutation,
          expiresAt: new Date(now.getTime() + 24 * 60 * 60 * 1_000),
        };
        await this.store.saveToolRequest(
          request,
          now,
          lease.epoch,
        );
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
