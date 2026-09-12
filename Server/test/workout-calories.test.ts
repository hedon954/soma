import assert from "node:assert/strict";
import { test } from "node:test";
import { validateDeviceTool } from "../src/tool-registry.js";

for (const name of ["create_workout", "update_workout"]) {
  for (const calories of [432, undefined]) {
    test(`${name} accepts ${calories === undefined ? "omitted" : "explicit"} calories`, () => {
      const workout = {
        exercise_id: 7,
        target_kind: "duration",
        laterality: "none",
        set_entries: [{
          logical_set_index: 1,
          side: "none",
          target_kind: "duration",
          duration_seconds: 1_200,
          external_weight_kg: 0,
        }],
        ...(calories === undefined ? {} : { calories }),
      };
      const args = name === "create_workout"
        ? { workouts: [workout] }
        : { record_id: 9, ...workout };
      assert.doesNotThrow(() => validateDeviceTool({
        name,
        schemaVersion: 4,
        arguments: args,
        allowedNames: [name],
      }));
    });
  }
}
