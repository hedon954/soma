import { ProtocolError } from "./domain.js";

export interface DeviceToolDefinition {
  name: string;
  schemaVersion: 1;
  mutation: boolean;
  parameters: {
    type: "object";
    properties: Record<string, Record<string, unknown>>;
    required?: string[];
    additionalProperties: false;
  };
}

const stringValue = { type: "string" };
const numberValue = { type: "number" };
const integerValue = { type: "integer" };
const booleanValue = { type: "boolean" };
const setEntries = {
  type: "array",
  items: {
    type: "object",
    properties: {
      reps: integerValue,
      external_weight_kg: numberValue,
    },
    additionalProperties: false,
  },
};
const templateExercises = {
  type: "array",
  items: {
    type: "object",
    properties: {
      exercise_id: stringValue,
      order: integerValue,
      target_sets: integerValue,
      target_reps: integerValue,
      target_weight_kg: numberValue,
      target_rest_seconds: integerValue,
      first_set_is_warmup: booleanValue,
      equipment_kind: stringValue,
      notes: stringValue,
    },
    required: ["exercise_id", "order"],
    additionalProperties: false,
  },
};
function parameters(
  properties: Record<string, Record<string, unknown>>,
  required: string[] = [],
): DeviceToolDefinition["parameters"] {
  return {
    type: "object",
    properties,
    ...(required.length === 0 ? {} : { required }),
    additionalProperties: false,
  };
}

const definitions: DeviceToolDefinition[] = [
  {
    name: "load_skill",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters({ skill_id: stringValue }, ["skill_id"]),
  },
  {
    name: "query_user_data",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters(
      {
        scope: stringValue,
        exercise_id: stringValue,
        program_id: stringValue,
        session_id: stringValue,
        limit: integerValue,
      },
      ["scope"],
    ),
  },
  {
    name: "list_exercise_names",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters({}),
  },
  {
    name: "record_workout",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters({
      exercise_id: stringValue,
      exercise_name: stringValue,
      set_entries: setEntries,
      rest_seconds: integerValue,
      duration_minutes: integerValue,
      form_score: integerValue,
      intensity: stringValue,
      feedback: stringValue,
    }),
  },
  {
    name: "record_meal",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        meal_type: stringValue,
        title: stringValue,
        calories: integerValue,
        protein: numberValue,
        carbs: numberValue,
        fat: numberValue,
        note: stringValue,
      },
      ["title", "calories"],
    ),
  },
  {
    name: "record_body",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters({
      weight: numberValue,
      body_fat: numberValue,
      waist: numberValue,
      posture_note: stringValue,
      safety_note: stringValue,
    }),
  },
  {
    name: "update_workout",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        record_id: stringValue,
        exercise_id: stringValue,
        set_entries: setEntries,
        rest_seconds: integerValue,
        duration_minutes: integerValue,
        form_score: integerValue,
        intensity: stringValue,
        feedback: stringValue,
      },
      ["record_id"],
    ),
  },
  {
    name: "update_meal",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        record_id: stringValue,
        meal_type: stringValue,
        title: stringValue,
        calories: integerValue,
        protein: numberValue,
        carbs: numberValue,
        fat: numberValue,
        note: stringValue,
      },
      ["record_id"],
    ),
  },
  {
    name: "update_body",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        record_id: stringValue,
        weight: numberValue,
        body_fat: numberValue,
        waist: numberValue,
        posture_note: stringValue,
        safety_note: stringValue,
      },
      ["record_id"],
    ),
  },
  {
    name: "delete_record",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      { record_type: stringValue, record_id: stringValue },
      ["record_type", "record_id"],
    ),
  },
  {
    name: "update_gym",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters({
      gym_name: stringValue,
      summary: stringValue,
      media_source: stringValue,
      equipment: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: stringValue,
            category: stringValue,
            capabilities: stringValue,
            confidence: numberValue,
          },
          required: ["name", "category", "capabilities"],
          additionalProperties: false,
        },
      },
    }),
  },
  {
    name: "switch_gym",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters({ gym_name: stringValue }, ["gym_name"]),
  },
  {
    name: "create_training_program",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        program_name: stringValue,
        goal: stringValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercises,
      },
      ["program_name", "template_name", "template_exercises"],
    ),
  },
  {
    name: "create_workout_template_version",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        program_id: stringValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercises,
      },
      ["program_id", "template_name", "template_exercises"],
    ),
  },
  {
    name: "update_workout_template",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        program_id: stringValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercises,
      },
      ["program_id", "template_name", "template_exercises"],
    ),
  },
  {
    name: "archive_training_program",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters({ program_id: stringValue }, ["program_id"]),
  },
  {
    name: "record_performance_analysis",
    schemaVersion: 1,
    mutation: true,
    parameters: parameters(
      {
        performance_id: stringValue,
        input_fingerprint: stringValue,
        evidence: stringValue,
        limitations: stringValue,
        feedback: stringValue,
      },
      [
        "performance_id",
        "input_fingerprint",
        "evidence",
        "limitations",
        "feedback",
      ],
    ),
  },
];

export const deviceToolRegistry = new Map(
  definitions.map((definition) => [definition.name, definition]),
);

export function validateDeviceTool(input: {
  name: string;
  schemaVersion: number;
  arguments: Record<string, unknown>;
  allowedNames: string[];
}): DeviceToolDefinition {
  const definition = deviceToolRegistry.get(input.name);
  if (
    definition === undefined ||
    definition.schemaVersion !== input.schemaVersion ||
    !input.allowedNames.includes(input.name)
  ) {
    throw new ProtocolError(
      "tool_schema_unsupported",
      "设备不支持该 Tool Schema。",
      409,
    );
  }
  const keys = Object.keys(input.arguments);
  const unknown = keys.find(
    (key) => definition.parameters.properties[key] === undefined,
  );
  const missing = definition.parameters.required?.find(
    (key) => input.arguments[key] === undefined,
  );
  if (unknown !== undefined || missing !== undefined) {
    throw new ProtocolError(
      "tool_schema_unsupported",
      "Tool 参数不符合固定 Schema。",
      409,
    );
  }
  rejectForbiddenValues(input.arguments);
  return definition;
}

function rejectForbiddenValues(
  value: Record<string, unknown> | unknown[],
): void {
  for (const [key, item] of Object.entries(value)) {
    const normalized = key.toLowerCase();
    if (
      normalized.includes("api_key") ||
      normalized.includes("authorization") ||
      normalized.includes("file_path") ||
      normalized.includes("local_path") ||
      normalized.includes("url")
    ) {
      throw new ProtocolError(
        "invalid_request",
        "Tool 参数包含不允许的设备路径、URL 或密钥字段。",
        400,
      );
    }
    if (item !== null && typeof item === "object") {
      rejectForbiddenValues(
        item as Record<string, unknown> | unknown[],
      );
    }
  }
}
