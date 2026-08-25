import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  timingSafeEqual,
  verify,
} from "node:crypto";
import type { SomaStore } from "./store-contract.js";
import { ProtocolError } from "./domain.js";

interface TokenClaims {
  deviceID: string;
  type: "access" | "rotation";
  exp: number;
  jti: string;
}

export interface AttestationAdapter {
  verifyRegistration(input: {
    deviceID: string;
    challenge: string;
    attestationObject?: string;
    keyID?: string;
  }): Promise<void>;
}

export class AllowDevelopmentAttestation implements AttestationAdapter {
  async verifyRegistration(): Promise<void> {}
}

export class RequiredAppAttestAdapter implements AttestationAdapter {
  constructor(
    private readonly verifyAppAttest: (
      input: Parameters<AttestationAdapter["verifyRegistration"]>[0],
    ) => Promise<boolean>,
  ) {}

  async verifyRegistration(
    input: Parameters<AttestationAdapter["verifyRegistration"]>[0],
  ): Promise<void> {
    if (!(await this.verifyAppAttest(input))) {
      throw new ProtocolError(
        "unauthorized_device",
        "App Attest 验证失败。",
        401,
      );
    }
  }
}

export class DeviceIdentityService {
  constructor(
    private readonly store: SomaStore,
    private readonly tokenSecret: string,
    private readonly attestation: AttestationAdapter,
    private readonly bundleID = "top.hedon.soma",
  ) {
    if (tokenSecret.length < 32) {
      throw new Error("SOMA_TOKEN_SECRET must contain at least 32 characters");
    }
  }

  async createChallenge(now = new Date()): Promise<{
    challengeID: string;
    challenge: string;
    expiresAt: Date;
  }> {
    const value = {
      challengeID: randomUUID(),
      challenge: randomBytes(32).toString("base64url"),
      expiresAt: new Date(now.getTime() + 5 * 60 * 1_000),
    };
    await this.store.saveChallenge({
      id: value.challengeID,
      challenge: value.challenge,
      expiresAt: value.expiresAt,
    });
    return value;
  }

  async register(
    input: {
      challengeID: string;
      deviceID: string;
      publicKeyPem: string;
      signature: string;
      timestamp: number;
      protocolVersion: number;
      attestationObject?: string;
      attestationKeyID?: string;
    },
    now = new Date(),
  ): Promise<{ accessToken: string; rotationToken: string; expiresAt: Date }> {
    if (Math.abs(now.getTime() - input.timestamp * 1_000) > 5 * 60 * 1_000) {
      throw new ProtocolError("invalid_request", "注册时间已过期。", 400);
    }
    const challenge = await this.store.consumeChallenge(
      input.challengeID,
      now,
    );
    const signed = [
      challenge.challenge,
      input.deviceID,
      this.bundleID,
      String(input.protocolVersion),
      String(input.timestamp),
    ].join("\n");
    const signature = Buffer.from(input.signature, "base64");
    const valid = verify(
      "sha256",
      Buffer.from(signed),
      input.publicKeyPem,
      signature,
    );
    if (!valid) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备签名无效。",
        401,
      );
    }
    await this.attestation.verifyRegistration({
      deviceID: input.deviceID,
      challenge: challenge.challenge,
      ...(input.attestationObject === undefined
        ? {}
        : { attestationObject: input.attestationObject }),
      ...(input.attestationKeyID === undefined
        ? {}
        : { keyID: input.attestationKeyID }),
    });
    await this.store.saveDevice(
      input.deviceID,
      input.publicKeyPem,
      input.attestationKeyID,
      now,
    );
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1_000);
    return {
      accessToken: this.issueToken(
        input.deviceID,
        "access",
        Math.floor(expiresAt.getTime() / 1_000),
      ),
      rotationToken: this.issueToken(
        input.deviceID,
        "rotation",
        Math.floor(now.getTime() / 1_000) + 30 * 24 * 60 * 60,
      ),
      expiresAt,
    };
  }

  async rotate(
    rotationToken: string,
    now = new Date(),
  ): Promise<{ accessToken: string; expiresAt: Date; deviceID: string }> {
    const claims = this.verifyToken(rotationToken, "rotation", now);
    if ((await this.store.devicePublicKey(claims.deviceID)) === undefined) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备身份已失效。",
        401,
      );
    }
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1_000);
    return {
      accessToken: this.issueToken(
        claims.deviceID,
        "access",
        Math.floor(expiresAt.getTime() / 1_000),
      ),
      expiresAt,
      deviceID: claims.deviceID,
    };
  }

  async authenticate(
    input: {
      authorization?: string;
      deviceID?: string;
      timestamp?: string;
      nonce?: string;
      bodyDigest?: string;
      signature?: string;
      method: string;
      path: string;
      rawBody: Buffer;
    },
    now = new Date(),
  ): Promise<string> {
    const token = input.authorization?.replace(/^Bearer\s+/i, "");
    if (
      token === undefined ||
      input.deviceID === undefined ||
      input.timestamp === undefined ||
      input.nonce === undefined ||
      input.bodyDigest === undefined ||
      input.signature === undefined
    ) {
      throw new ProtocolError(
        "unauthorized_device",
        "缺少设备认证信息。",
        401,
      );
    }
    const claims = this.verifyToken(token, "access", now);
    if (claims.deviceID !== input.deviceID) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备身份不匹配。",
        401,
      );
    }
    const timestamp = Number(input.timestamp);
    if (
      !Number.isFinite(timestamp) ||
      Math.abs(now.getTime() - timestamp * 1_000) > 5 * 60 * 1_000
    ) {
      throw new ProtocolError(
        "unauthorized_device",
        "请求时间已过期。",
        401,
      );
    }
    const actualDigest = sha256(input.rawBody);
    if (!safeEqual(actualDigest, input.bodyDigest)) {
      throw new ProtocolError("invalid_request", "请求摘要不匹配。", 400);
    }
    const publicKey = await this.store.devicePublicKey(input.deviceID);
    if (publicKey === undefined) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备身份已失效。",
        401,
      );
    }
    const canonical = [
      input.method.toUpperCase(),
      input.path,
      input.timestamp,
      input.nonce,
      input.bodyDigest,
    ].join("\n");
    if (
      !verify(
        "sha256",
        Buffer.from(canonical),
        publicKey,
        Buffer.from(input.signature, "base64"),
      )
    ) {
      throw new ProtocolError("unauthorized_device", "请求签名无效。", 401);
    }
    const consumed = await this.store.consumeNonce(
      input.deviceID,
      input.nonce,
      new Date(now.getTime() + 10 * 60 * 1_000),
    );
    if (!consumed) {
      throw new ProtocolError("replay_detected", "请求 nonce 已使用。", 409);
    }
    return input.deviceID;
  }

  private issueToken(
    deviceID: string,
    type: TokenClaims["type"],
    exp: number,
  ): string {
    const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" }))
      .toString("base64url");
    const payload = Buffer.from(
      JSON.stringify({ deviceID, type, exp, jti: randomUUID() }),
    ).toString("base64url");
    const signature = createHmac("sha256", this.tokenSecret)
      .update(`${header}.${payload}`)
      .digest("base64url");
    return `${header}.${payload}.${signature}`;
  }

  private verifyToken(
    token: string,
    expectedType: TokenClaims["type"],
    now: Date,
  ): TokenClaims {
    const parts = token.split(".");
    if (parts.length !== 3) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备 token 无效。",
        401,
      );
    }
    const [header, payload, supplied] = parts as [string, string, string];
    const expected = createHmac("sha256", this.tokenSecret)
      .update(`${header}.${payload}`)
      .digest("base64url");
    if (!safeEqual(expected, supplied)) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备 token 无效。",
        401,
      );
    }
    const claims = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as TokenClaims;
    if (
      claims.type !== expectedType ||
      claims.exp <= Math.floor(now.getTime() / 1_000)
    ) {
      throw new ProtocolError(
        "unauthorized_device",
        "设备 token 已过期。",
        401,
      );
    }
    return claims;
  }
}

export function sha256(value: Buffer | string): string {
  return createHash("sha256").update(value).digest("hex");
}

export class TokenCipher {
  private readonly key: Buffer;

  constructor(key: string) {
    const decoded = Buffer.from(key, "base64");
    if (decoded.length !== 32) {
      throw new Error("SOMA_TOKEN_ENCRYPTION_KEY must be 32 bytes in base64");
    }
    this.key = decoded;
  }

  encrypt(value: string): string {
    const nonce = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, nonce);
    const ciphertext = Buffer.concat([
      cipher.update(value, "utf8"),
      cipher.final(),
    ]);
    return Buffer.concat([
      nonce,
      cipher.getAuthTag(),
      ciphertext,
    ]).toString("base64");
  }

  decrypt(value: string): string {
    const envelope = Buffer.from(value, "base64");
    const nonce = envelope.subarray(0, 12);
    const tag = envelope.subarray(12, 28);
    const ciphertext = envelope.subarray(28);
    const decipher = createDecipheriv("aes-256-gcm", this.key, nonce);
    decipher.setAuthTag(tag);
    return Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]).toString("utf8");
  }
}

function safeEqual(lhs: string, rhs: string): boolean {
  const left = Buffer.from(lhs);
  const right = Buffer.from(rhs);
  return left.length === right.length && timingSafeEqual(left, right);
}
