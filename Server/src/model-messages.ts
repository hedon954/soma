import { ProtocolError, type AgentModelMessage } from "./domain.js";

export function parseModelMessages(raw: unknown[], version: number): AgentModelMessage[] {
  const invalid = (): never => { throw new ProtocolError("invalid_request", "模型历史消息或工具配对无效。", 400); };
  const pending = new Set<string>();
  const messages = raw.map((item): AgentModelMessage => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) return invalid();
    const value = item as Record<string, unknown>;
    if (typeof value.role !== "string" || !["system", "user", "assistant", ...(version >= 3 ? ["tool"] : [])].includes(value.role)
      || typeof value.text !== "string" || !Array.isArray(value.mediaIDs)
      || value.mediaIDs.some(id => typeof id !== "string")) return invalid();
    const message: AgentModelMessage = {
      role: value.role as AgentModelMessage["role"], text: value.text, mediaIDs: value.mediaIDs as string[],
    };
    if (message.role !== "user" && message.mediaIDs.length > 0) return invalid();
    if (message.role === "tool") {
      if (typeof value.toolCallID !== "string" || !pending.delete(value.toolCallID) || value.toolCalls !== undefined) return invalid();
      message.toolCallID = value.toolCallID;
    } else {
      if (pending.size !== 0 || value.toolCallID !== undefined) return invalid();
      if (value.toolCalls !== undefined) {
        if (version < 3 || message.role !== "assistant" || !Array.isArray(value.toolCalls) || value.toolCalls.length === 0) return invalid();
        message.toolCalls = value.toolCalls.map((rawCall) => {
          if (rawCall === null || typeof rawCall !== "object") return invalid();
          const call = rawCall as Record<string, unknown>;
          if (typeof call.id !== "string" || !call.id || pending.has(call.id)
            || typeof call.name !== "string" || !call.name || typeof call.arguments !== "string") return invalid();
          pending.add(call.id);
          return { id: call.id, name: call.name, arguments: call.arguments };
        });
      }
    }
    return message;
  });
  if (pending.size !== 0 || messages[0]?.role !== "system" || messages.at(-1)?.role !== "user"
    || messages.slice(1).some(message => message.role === "system")) return invalid();
  return messages;
}
