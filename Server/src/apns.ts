import {
  createPrivateKey,
  randomUUID,
  sign,
} from "node:crypto";
import { connect } from "node:http2";
import type { ActivityToken, AgentEvent } from "./domain.js";
import type { TokenCipher } from "./security.js";
import type { SomaStore } from "./store-contract.js";

export interface APNsProvider {
  sendActivityUpdate(input: {
    token: string;
    environment: ActivityToken["environment"];
    sequence: number;
    state: {
      phaseRaw: string;
      operationCount: number;
      queuedCount: number;
      sequence: number;
      isStale: boolean;
    };
    end: boolean;
  }): Promise<"accepted" | "unregistered" | "retry">;
}

export class NoopAPNsProvider implements APNsProvider {
  async sendActivityUpdate(): Promise<"accepted"> {
    return "accepted";
  }
}

export class AppleAPNsProvider implements APNsProvider {
  private cachedJWT?: { value: string; issuedAt: number };

  constructor(
    private readonly teamID: string,
    private readonly keyID: string,
    private readonly bundleID: string,
    private readonly privateKeyPEM: string,
  ) {}

  async sendActivityUpdate(
    input: Parameters<APNsProvider["sendActivityUpdate"]>[0],
  ): Promise<"accepted" | "unregistered" | "retry"> {
    const authority =
      input.environment === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com";
    const client = connect(authority);
    try {
      const response = await new Promise<{
        status: number;
        reason?: string;
      }>((resolve, reject) => {
        const request = client.request({
          ":method": "POST",
          ":path": `/3/device/${input.token}`,
          authorization: `bearer ${this.providerJWT()}`,
          "apns-id": randomUUID(),
          "apns-push-type": "liveactivity",
          "apns-priority": "10",
          "apns-topic": `${this.bundleID}.push-type.liveactivity`,
        });
        const chunks: Buffer[] = [];
        let status = 500;
        request.on("response", (headers) => {
          status = Number(headers[":status"] ?? 500);
        });
        request.on("data", (chunk: Buffer) => chunks.push(chunk));
        request.on("error", reject);
        request.on("end", () => {
          let reason: string | undefined;
          try {
            const body = JSON.parse(Buffer.concat(chunks).toString("utf8")) as {
              reason?: string;
            };
            reason = body.reason;
          } catch {
            // Successful APNs responses have an empty body.
          }
          resolve({
            status,
            ...(reason === undefined ? {} : { reason }),
          });
        });
        request.end(JSON.stringify({
          aps: {
            timestamp: Math.floor(Date.now() / 1_000),
            event: input.end ? "end" : "update",
            "content-state": input.state,
            ...(input.end
              ? {
                  "dismissal-date": Math.floor(Date.now() / 1_000) + 60,
                  alert: {
                    title: "Soma 后台任务已结束",
                    body:
                      input.state.phaseRaw === "succeeded"
                        ? "结果已准备好，打开 Soma 即可查看。"
                        : "打开 Soma 查看任务状态和恢复建议。",
                  },
                }
              : {
                  "stale-date": Math.floor(Date.now() / 1_000) + 15 * 60,
                }),
          },
        }));
      });
      if (response.status === 200) return "accepted";
      if (
        response.status === 410 ||
        response.reason === "Unregistered" ||
        response.reason === "BadDeviceToken" ||
        response.reason === "DeviceTokenNotForTopic" ||
        response.reason === "BadTopic"
      ) {
        return "unregistered";
      }
      return "retry";
    } finally {
      client.close();
    }
  }

  private providerJWT(): string {
    const now = Math.floor(Date.now() / 1_000);
    if (
      this.cachedJWT !== undefined &&
      now - this.cachedJWT.issuedAt < 50 * 60
    ) {
      return this.cachedJWT.value;
    }
    const header = Buffer.from(
      JSON.stringify({ alg: "ES256", kid: this.keyID }),
    ).toString("base64url");
    const claims = Buffer.from(
      JSON.stringify({ iss: this.teamID, iat: now }),
    ).toString("base64url");
    const signingInput = `${header}.${claims}`;
    const signature = sign(
      "sha256",
      Buffer.from(signingInput),
      {
        key: createPrivateKey(this.privateKeyPEM),
        dsaEncoding: "ieee-p1363",
      },
    ).toString("base64url");
    const value = `${signingInput}.${signature}`;
    this.cachedJWT = { value, issuedAt: now };
    return value;
  }
}

export class ActivityPushProjector {
  constructor(
    private readonly store: SomaStore,
    private readonly provider: APNsProvider,
    private readonly tokenCipher: TokenCipher,
  ) {}

  async project(
    jobID: string,
    event: AgentEvent,
  ): Promise<"delivered" | "dropped" | "retry" | "noop"> {
    const token = await this.store.activityToken(jobID);
    if (
      token === undefined ||
      event.sequence <= token.lastPushedSequence
    ) {
      return "noop";
    }
    const phaseRaw = phaseFromEvent(event);
    const terminal =
      event.phase === "completed" ||
      event.phase === "failed" ||
      event.phase === "cancelled";
    const result = await this.provider.sendActivityUpdate({
      token: this.tokenCipher.decrypt(token.encryptedToken),
      environment: token.environment,
      sequence: event.sequence,
      state: {
        phaseRaw,
        operationCount: event.sequence,
        queuedCount: 0,
        sequence: event.sequence,
        isStale: false,
      },
      end: terminal,
    });
    if (result === "unregistered" || terminal) {
      await this.store.deleteActivityToken(jobID);
      return result === "unregistered" ? "dropped" : "delivered";
    } else if (result === "accepted") {
      token.lastPushedSequence = event.sequence;
      await this.store.saveActivityToken(token);
      return "delivered";
    }
    return "retry";
  }
}

export class OutboxDispatcher {
  constructor(
    private readonly store: SomaStore,
    private readonly activity: ActivityPushProjector,
  ) {}

  async runBatch(now = new Date(), limit = 100): Promise<number> {
    const messages = await this.store.outboxBatch(now, limit);
    for (const message of messages) {
      try {
        let outcome: "delivered" | "dropped" | "retry" | "noop" = "noop";
        if (
          message.topic === "apns" &&
          typeof message.payload.sequence === "number"
        ) {
          const event = (
            await this.store.events(
              message.aggregateID,
              message.payload.sequence - 1,
              1,
            )
          )[0];
          if (event !== undefined) {
            outcome = await this.activity.project(message.aggregateID, event);
          }
        }
        if (outcome === "retry") {
          await this.store.markOutboxRetry(
            message.id,
            retryDate(now, message.attemptCount),
          );
        } else {
          await this.store.markOutboxPublished(message.id, now);
        }
      } catch {
        await this.store.markOutboxRetry(
          message.id,
          retryDate(now, message.attemptCount),
        );
      }
    }
    return messages.length;
  }
}

function retryDate(now: Date, attemptCount: number): Date {
  const seconds = Math.min(15 * 60, 2 ** Math.min(attemptCount, 9));
  return new Date(now.getTime() + seconds * 1_000);
}

function phaseFromEvent(event: AgentEvent): string {
  if (event.phase === "failed") return "failed";
  if (event.phase === "cancelled") return "cancelled";
  if (event.kind === "output" && event.phase === "completed") {
    return "succeeded";
  }
  if (event.kind === "tool" && event.phase === "suspended") {
    return "waitingForDevice";
  }
  return "running";
}
