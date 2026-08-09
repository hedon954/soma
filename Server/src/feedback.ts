import { createHash } from "node:crypto";
import { ProtocolError } from "./domain.js";

export const feedbackRecipient = "hedonwang@gmail.com";
export const feedbackSender = feedbackRecipient;
export const maximumFeedbackMessageCharacters = 5_000;
export const maximumFeedbackAttachmentCount = 10;
export const maximumFeedbackAttachmentBytes = 25 * 1_024 * 1_024;

export interface FeedbackEmailAttachment {
  filename: string;
  contentType: string;
  content: Buffer;
}

export interface FeedbackEmailInput {
  idempotencyKey: string;
  message: string;
  attachments: FeedbackEmailAttachment[];
}

export interface FeedbackEmailProvider {
  send(input: FeedbackEmailInput): Promise<void>;
}

export class GmailFeedbackEmailProvider implements FeedbackEmailProvider {
  constructor(
    private readonly clientID: string,
    private readonly clientSecret: string,
    private readonly refreshToken: string,
    private readonly tokenEndpoint = "https://oauth2.googleapis.com/token",
    private readonly sendEndpoint =
      "https://gmail.googleapis.com/upload/gmail/v1/users/hedonwang%40gmail.com/messages/send?uploadType=media",
  ) {}

  async send(input: FeedbackEmailInput): Promise<void> {
    try {
      const accessToken = await this.accessToken();
      const message = buildGmailMessage(input);
      const response = await fetch(this.sendEndpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "message/rfc822",
          "content-length": String(message.length),
        },
        body: message,
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) throw providerUnavailable();
    } catch (error) {
      if (error instanceof ProtocolError) throw error;
      throw providerUnavailable();
    }
  }

  private async accessToken(): Promise<string> {
    const response = await fetch(this.tokenEndpoint, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientID,
        client_secret: this.clientSecret,
        refresh_token: this.refreshToken,
        grant_type: "refresh_token",
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw providerUnavailable();
    const payload = (await response.json()) as { access_token?: unknown };
    if (typeof payload.access_token !== "string" || payload.access_token === "") {
      throw providerUnavailable();
    }
    return payload.access_token;
  }
}

export function buildGmailMessage(input: FeedbackEmailInput): Buffer {
  const digest = createHash("sha256")
    .update(input.idempotencyKey)
    .digest("hex");
  const messageID = `<${digest}@soma.feedback>`;
  const subject = `=?UTF-8?B?${Buffer.from("Soma 用户反馈").toString("base64")}?=`;
  const text = input.message.length === 0 ? "（仅媒体反馈）" : input.message;
  const headers = [
    `From: ${feedbackSender}`,
    `To: ${feedbackRecipient}`,
    `Subject: ${subject}`,
    `Message-ID: ${messageID}`,
    "MIME-Version: 1.0",
  ];

  if (input.attachments.length === 0) {
    return Buffer.from([
      ...headers,
      "Content-Type: text/plain; charset=UTF-8",
      "Content-Transfer-Encoding: base64",
      "",
      encodeBase64Lines(Buffer.from(text)),
      "",
    ].join("\r\n"));
  }

  const boundary = `soma-feedback-${digest.slice(0, 32)}`;
  const lines = [
    ...headers,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    encodeBase64Lines(Buffer.from(text)),
  ];
  for (const attachment of input.attachments) {
    lines.push(
      `--${boundary}`,
      `Content-Type: ${attachment.contentType}; name="${attachment.filename}"`,
      `Content-Disposition: attachment; filename="${attachment.filename}"`,
      "Content-Transfer-Encoding: base64",
      "",
      encodeBase64Lines(attachment.content),
    );
  }
  lines.push(`--${boundary}--`, "");
  return Buffer.from(lines.join("\r\n"));
}

function encodeBase64Lines(content: Buffer): string {
  return content.toString("base64").match(/.{1,76}/g)?.join("\r\n") ?? "";
}

function providerUnavailable(): ProtocolError {
  return new ProtocolError(
    "provider_unavailable",
    "反馈暂时无法发送，请稍后重试。",
    502,
  );
}

export function feedbackFilename(
  position: number,
  contentType: string,
): string {
  const fileExtension = new Map([
    ["image/jpeg", "jpg"],
    ["image/heic", "heic"],
    ["image/png", "png"],
    ["video/quicktime", "mov"],
    ["video/mp4", "mp4"],
  ]).get(contentType);
  if (fileExtension === undefined) {
    throw new ProtocolError("invalid_request", "反馈媒体类型不受支持。", 400);
  }
  return `feedback-${position}.${fileExtension}`;
}
