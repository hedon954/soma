import { ProtocolError, type AgentEvent } from "./domain.js";

const stringValue = { type: "string" };
export const userQuestionsParameters = {
  type: "object" as const,
  properties: {
    questions: {
      type: "array", minItems: 1, maxItems: 3,
      items: {
        type: "object",
        properties: {
          id: stringValue,
          question: stringValue,
          options: {
            type: "array", maxItems: 6,
            items: {
              type: "object",
              properties: {
                id: stringValue,
                text: stringValue,
                action: {
                  type: "object",
                  properties: { tool_name: stringValue, arguments_json: stringValue },
                  required: ["tool_name", "arguments_json"],
                  additionalProperties: false,
                },
              },
              required: ["id", "text"],
              additionalProperties: false,
            },
          },
          allows_custom_input: { type: "boolean" },
        },
        required: ["id", "question", "options", "allows_custom_input"],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false as const,
};

export function validateQuestionActions(
  args: Record<string, unknown>,
  validate: (name: string, args: Record<string, unknown>) => void,
): void {
  const questions = args.questions as Array<{
    id: string; question: string; allows_custom_input: boolean;
    options: Array<{ id: string; text: string; action?: { tool_name: string; arguments_json: string } }>;
  }>;
  const valid = (text: string, max: number) => text.trim().length > 0 && [...text].length <= max;
  if (new Set(questions.map((q) => q.id)).size !== questions.length) invalid();
  for (const question of questions) {
    if (!valid(question.id, 64) || !valid(question.question, 300)
      || (question.options.length === 0 && !question.allows_custom_input)
      || new Set(question.options.map((o) => o.id)).size !== question.options.length) invalid();
    for (const option of question.options) {
      if (!valid(option.id, 64) || !valid(option.text, 300)) invalid();
      if (option.action === undefined) continue;
      const action = option.action;
      if (["ask_user_questions", "load_skill", "submit_feedback", "record_performance_analysis"].includes(action.tool_name)
        || Buffer.byteLength(action.arguments_json, "utf8") > 32_768) invalid();
      let parsed: unknown;
      try { parsed = JSON.parse(action.arguments_json); } catch { invalid(); }
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) invalid();
      try { validate(action.tool_name, parsed as Record<string, unknown>); } catch { invalid(); }
    }
  }
}

export function completedQuestionAnswer(history: AgentEvent[]): string | undefined {
  const questionCalls = new Set(history
    .filter((event) => event.kind === "tool" && event.payload.toolName === "ask_user_questions")
    .map((event) => event.payload.toolCallID)
    .filter((id): id is string => typeof id === "string"));
  for (const event of [...history].reverse()) {
    if (event.kind !== "tool" || event.phase !== "completed"
      || typeof event.payload.toolCallID !== "string" || !questionCalls.has(event.payload.toolCallID)) continue;
    const result = event.payload.result as { ok?: boolean; code?: string; message?: string } | undefined;
    if (result?.ok === true && result.code === "user_questions" && typeof result.message === "string") {
      return result.message;
    }
  }
  return undefined;
}

function invalid(): never {
  throw new ProtocolError("tool_schema_unsupported", "Tool 参数不符合固定 Schema：请修正问题、选项和确定性参数。", 409);
}
