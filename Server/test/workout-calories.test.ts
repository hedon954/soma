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

for (const scope of ["active", "gross", "unknown", "metGross"]) {
  test(`update_workout calorie scope ${scope}`, () => {
    const validate = () => validateDeviceTool({
      name: "update_workout", schemaVersion: 4,
      arguments: { record_id: 9, target_kind: "duration", laterality: "none", calories: 500, calories_scope: scope },
      allowedNames: ["update_workout"],
    });
    if (scope === "metGross") assert.throws(validate);
    else assert.doesNotThrow(validate);
  });
}

test("energy context only accepts explicit typed facts", () => {
  const validate = (energy_context: Record<string, unknown>) => validateDeviceTool({
    name: "record_energy_context", schemaVersion: 1,
    arguments: { date_from: "2026-11-01", energy_context },
    allowedNames: ["record_energy_context"],
  });
  assert.doesNotThrow(() => validate({ work_posture: "sitting", food_complete: false }));
  assert.throws(() => validate({ food_complete: "true" }));
  assert.throws(() => validate({ factor: 1.8 }));
});
