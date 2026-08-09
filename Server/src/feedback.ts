import { ProtocolError } from "./domain.js";

export const feedbackRecipient = "hedonwang@gmail.com";
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

export class ResendFeedbackEmailProvider implements FeedbackEmailProvider {
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    private readonly endpoint = "https://api.resend.com/emails",
  ) {}

  async send(input: FeedbackEmailInput): Promise<void> {
    const response = await fetch(this.endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.apiKey}`,
        "content-type": "application/json",
        "idempotency-key": input.idempotencyKey,
      },
      body: JSON.stringify({
        from: this.from,
        to: [feedbackRecipient],
        subject: "Soma 用户反馈",
        text: input.message.length === 0 ? "（仅媒体反馈）" : input.message,
        attachments: input.attachments.map((attachment) => ({
          filename: attachment.filename,
          content: attachment.content.toString("base64"),
        })),
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) {
      throw new ProtocolError(
        "provider_unavailable",
        "反馈暂时无法发送，请稍后重试。",
        502,
      );
    }
  }
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
