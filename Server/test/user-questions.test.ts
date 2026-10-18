import assert from "node:assert/strict";
import { test } from "node:test";
import { validateDeviceTool } from "../src/tool-registry.js";
import type { AgentEvent } from "../src/domain.js";
import { completedQuestionAnswer } from "../src/user-questions.js";

function question(action?: { tool_name: string; arguments_json: string }) {
  return { id: "goal", question: "接下来做什么？", options: [
    { id: "talk", text: "我想聊聊恢复" },
    { id: "save", text: "帮我记录体重 68 千克", ...(action === undefined ? {} : { action }) },
  ], allows_custom_input: true };
}

function validate(questions: unknown[], allowedNames = ["ask_user_questions", "create_body_entry"]) {
  return validateDeviceTool({ name: "ask_user_questions", schemaVersion: 1, arguments: { questions }, allowedNames });
}

test("questions accept text, deterministic action and custom input", () => {
  const action = { tool_name: "create_body_entry", arguments_json: '{"weight":68}' };
  assert.doesNotThrow(() => validate([question(action)]));
  assert.doesNotThrow(() => validate([question()]));
  assert.doesNotThrow(() => validate([{ ...question(), options: [] }]));
});

test("questions reject recursive, invalid and unexposed bindings", () => {
  for (const action of [
    { tool_name: "ask_user_questions", arguments_json: '{}' },
    { tool_name: "submit_feedback", arguments_json: '{}' },
    { tool_name: "create_body_entry", arguments_json: '{"weight":"guess"}' },
    { tool_name: "create_body_entry", arguments_json: '{' },
  ]) assert.throws(() => validate([question(action)]));
  assert.throws(() => validate([question({ tool_name: "create_body_entry", arguments_json: '{"weight":68}' })], ["ask_user_questions"]));
});

test("selection questions stay free of tool actions", () => {
  const selected = { ...question(), selection: "single" };
  assert.doesNotThrow(() => validate([selected]));
  assert.throws(() => validate([{ ...selected, allows_custom_input: false }]));
  assert.throws(() => validate([{
    ...question({ tool_name: "create_body_entry", arguments_json: '{"weight":68}' }),
    selection: "single",
  }]));
  assert.throws(() => validate([
    selected,
    { ...question(), id: "place", question: "在哪练？" },
  ]));
});

test("questions require actionable unique bounded options", () => {
  assert.throws(() => validate([question(), question()]));
  assert.throws(() => validate([{ ...question(), options: [], allows_custom_input: false }]));
  assert.throws(() => validate([{ ...question(), options: Array.from({ length: 7 }, (_, i) => ({ id: String(i), text: "回答" })) }]));
});

test("question completion must match a question tool call", () => {
  const started: AgentEvent = {
    id: "event-start", jobID: "job", sequence: 1, kind: "tool", phase: "started", payloadVersion: 1,
    payload: { toolCallID: "question", toolName: "ask_user_questions" }, createdAt: new Date(),
  };
  const completed: AgentEvent = {
    ...started, id: "event-end", sequence: 2, phase: "completed",
    payload: { toolCallID: "question", result: { ok: true, code: "user_questions", message: "接下来想做什么？" } },
  };
  assert.equal(completedQuestionAnswer([started, completed]), "接下来想做什么？");
  assert.equal(completedQuestionAnswer([completed]), undefined);
  assert.equal(completedQuestionAnswer([started, { ...completed, payload: { ...completed.payload, toolCallID: "other" } }]), undefined);
});
