import assert from "node:assert/strict";
import test from "node:test";
import { parseModelMessages } from "../src/model-messages.js";

const system = { role: "system", text: "rules", mediaIDs: [] };
const user = { role: "user", text: "new turn", mediaIDs: [] };
const call = { role: "assistant", text: "", mediaIDs: [], toolCalls: [{ id: "call_1", name: "list_workouts", arguments: "{}" }] };
const result = { role: "tool", text: "{\"ok\":true}", mediaIDs: [], toolCallID: "call_1" };

test("v3 preserves historical native calls and results while v2 stays readable", () => {
  assert.deepEqual(parseModelMessages([system, user, call, result, user], 3), [system, user, call, result, user]);
  assert.deepEqual(parseModelMessages([system, user], 2), [system, user]);
});
test("rejects unpaired results, unfinished batches and tool frames in v2", () => {
  for (const messages of [[system, result, user], [system, user, call, user], [system, user, call, { ...result, toolCallID: "wrong" }, user]]) {
    assert.throws(() => parseModelMessages(messages, 3));
  }
  assert.throws(() => parseModelMessages([system, user, call, result, user], 2));
});
