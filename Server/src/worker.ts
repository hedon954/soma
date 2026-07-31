import { randomUUID } from "node:crypto";
import type { AgentEvent, AgentJob, ToolRequest } from "./domain.js";
import { isTerminal, ProtocolError } from "./domain.js";
import type { SomaStore } from "./store.js";
import { validateDeviceTool } from "./tool-registry.js";

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
  ): Promise<ProviderStep>;
}

export class DeterministicTestProvider implements ManagedModelProvider {
  constructor(private readonly step: ProviderStep = {
    kind: "completed",
    answer: "远程任务已完成。",
  }) {}

  async run(): Promise<ProviderStep> {
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
      payload: { provider: "managed", model: "configured" },
      createdAt: now,
    });
    try {
      const history = await this.store.events(job.id, 0, 500);
      const media = await this.mediaResolver.resolve(job);
      const step = await this.provider.run(job, history, media);
      if (step.kind === "deviceTool") {
        const definition = validateDeviceTool({
          name: step.toolName,
          schemaVersion: step.schemaVersion,
          arguments: step.arguments,
          allowedNames: job.input?.allowedDeviceTools ?? [],
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
          payload: { code },
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
    }
  }
}
