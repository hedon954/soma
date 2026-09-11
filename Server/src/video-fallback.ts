import { ProtocolError, type AgentModelMessage } from "./domain.js";
import type { ProviderMedia } from "./worker.js";

export interface VideoFrameFallback {
  videoID: string;
  frameIDs: string[];
  timestampsSeconds: number[];
  durationSeconds: number;
}

export function parseVideoFallbacks(
  raw: unknown,
  messages: AgentModelMessage[],
): VideoFrameFallback[] {
  if (raw === undefined) return [];
  const invalid = (): never => {
    throw new ProtocolError("invalid_request", "视频备用画面清单无效。请重新发送视频。", 400);
  };
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 3) return invalid();
  const videos = new Set<string>();
  const frames = new Set<string>();
  const primaryIDs = new Set(messages.flatMap((message) => message.mediaIDs));
  return raw.map((item: unknown) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) return invalid();
    const value = item as Record<string, unknown>;
    const { videoID, frameIDs, timestampsSeconds, durationSeconds } = value;
    if (typeof videoID !== "string" || videos.has(videoID) ||
        messages.filter((message) => message.role === "user" && message.mediaIDs.includes(videoID)).length !== 1 ||
        !Array.isArray(frameIDs) || frameIDs.length < 8 || frameIDs.length > 24 ||
        !Array.isArray(timestampsSeconds) || timestampsSeconds.length !== frameIDs.length ||
        typeof durationSeconds !== "number" || !Number.isFinite(durationSeconds) || durationSeconds <= 0) return invalid();
    videos.add(videoID);
    let previous = -1;
    for (const time of timestampsSeconds as unknown[]) {
      if (typeof time !== "number" || !Number.isFinite(time) || time < 0 || time >= durationSeconds || time < previous) return invalid();
      previous = time;
    }
    for (const id of frameIDs as unknown[]) {
      if (typeof id !== "string" || id.length === 0 || frames.has(id) || primaryIDs.has(id)) return invalid();
      frames.add(id);
      if (frames.size > 24) return invalid();
    }
    return { videoID, frameIDs: frameIDs as string[], timestampsSeconds: timestampsSeconds as number[], durationSeconds };
  });
}

export function checkedFallbackMedia(
  manifests: VideoFrameFallback[], media: ProviderMedia[], referencedVideoIDs: string[],
): Map<string, VideoFrameFallback> {
  const fail = (): never => {
    throw new ProtocolError("video_fallback_unavailable", "当前模型不支持完整视频，备用画面也不可用。请重新发送视频或更换模型。", 422);
  };
  const byID = new Map(media.map((item) => [item.id, item]));
  const result = new Map(manifests.map((value) => [value.videoID, value]));
  if (referencedVideoIDs.length === 0 || referencedVideoIDs.some((id) => !result.has(id))) return fail();
  let totalBytes = 0;
  for (const manifest of manifests) {
    if (!referencedVideoIDs.includes(manifest.videoID)) return fail();
    for (const id of manifest.frameIDs) {
      const frame = byID.get(id);
      if (frame?.contentType !== "image/jpeg" || frame.byteLength === undefined ||
          !Number.isSafeInteger(frame.byteLength) || frame.byteLength <= 0) return fail();
      totalBytes += frame.byteLength;
    }
  }
  if (totalBytes > 8 * 1024 * 1024) return fail();
  return result;
}

export function explicitlyRejectsVideo(status: number, message: string): boolean {
  if (![400, 415, 422].includes(status)) return false;
  const text = message.toLowerCase();
  const mentionsVideo = ["video_url", "video input", "video is not supported", "video content", "不支持视频"]
    .some((value) => text.includes(value));
  const rejectsType = ["unknown variant", "unsupported", "not support", "doesn't support", "unrecognized",
    "not allowed", "unexpected", "invalid content type", "不支持"].some((value) => text.includes(value));
  return mentionsVideo && rejectsType;
}

export async function boundedProviderError(response: Response): Promise<string> {
  const reader = response.body?.getReader();
  if (reader === undefined) return "";
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (length < 4096) {
      const next = await reader.read();
      if (next.done) break;
      const chunk = next.value.subarray(0, 4096 - length);
      chunks.push(chunk);
      length += chunk.length;
    }
  } finally {
    await reader.cancel().catch(() => undefined);
    reader.releaseLock();
  }
  const data = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder().decode(data);
}

export function frameFallbackPrompt(manifest: VideoFrameFallback): string {
  return `[SOMA VIDEO FRAME FALLBACK v1]\n当前视频改用 ${manifest.frameIDs.length} 张画面，覆盖 ${manifest.durationSeconds} 秒。` +
    "本说明替代此前完整视频直传说明。只能观察静态画面，不能声称观看了完整视频或确定完整动作节奏、速度与连续轨迹。" +
    `画面时间（秒）：${manifest.timestampsSeconds.join("、")}。遵循原有授权和工具结果，不重复写入。`;
}
