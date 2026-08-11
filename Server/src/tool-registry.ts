import { ProtocolError } from "./domain.js";
import type { AgentEvent } from "./domain.js";

export interface DeviceToolDefinition {
  name: string;
  description?: string;
  schemaVersion: 1 | 2;
  mutation: boolean;
  parameters: {
    type: "object";
    properties: Record<string, Record<string, unknown>>;
    required?: string[];
    additionalProperties: false;
  };
}

const expandableTools: Record<string, string[]> = {
  plans: [
    "create_training_program",
    "create_workout_template_version",
    "archive_training_program",
    "delete_training_program",
    "start_guided_workout",
  ],
  gym: ["update_gym", "switch_gym"],
  review: ["record_performance_analysis"],
  feedback: ["submit_feedback"],
};

export function effectiveAllowedDeviceTools(
  initial: string[],
  events: AgentEvent[],
): string[] {
  const names = new Set(initial);
  const completed = new Set(
    events
      .filter((event) =>
        event.kind === "tool" &&
        event.phase === "completed" &&
        event.payload.result !== undefined &&
        (event.payload.result as { ok?: unknown }).ok !== false
      )
      .map((event) => event.payload.toolCallID)
      .filter((value): value is string => typeof value === "string"),
  );
  for (const event of events) {
    if (
      event.kind !== "tool" ||
      event.phase !== "suspended" ||
      event.payload.toolName !== "expand_tool_group" ||
      typeof event.payload.toolCallID !== "string" ||
      !completed.has(event.payload.toolCallID)
    ) {
      continue;
    }
    const argumentsValue = event.payload.arguments;
    if (
      argumentsValue === null ||
      typeof argumentsValue !== "object" ||
      Array.isArray(argumentsValue)
    ) {
      continue;
    }
    const group = (argumentsValue as Record<string, unknown>).tool_group;
    if (typeof group !== "string") continue;
    for (const name of expandableTools[group] ?? []) names.add(name);
  }
  return [...names];
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
const mealItems = {
  type: "array",
  items: {
    type: "object",
    properties: {
      id: stringValue,
      name: stringValue,
      portion_description: stringValue,
      calories: integerValue,
      protein: numberValue,
      carbs: numberValue,
      fat: numberValue,
    },
    required: ["name"],
    additionalProperties: false,
  },
};
const mutationPayload = {
  type: "object",
  properties: {
    exercise_id: stringValue,
    exercise_name: stringValue,
    set_entries: setEntries,
    rest_seconds: integerValue,
    duration_minutes: integerValue,
    form_score: integerValue,
    intensity: stringValue,
    feedback: stringValue,
    meal_type: stringValue,
    title: stringValue,
    calories: integerValue,
    protein: numberValue,
    carbs: numberValue,
    fat: numberValue,
    items: mealItems,
    note: stringValue,
    weight: numberValue,
    body_fat: numberValue,
    waist: numberValue,
    posture_note: stringValue,
    safety_note: stringValue,
  },
  additionalProperties: false,
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
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({ skill_id: stringValue }, ["skill_id"]),
  },
  {
    name: "expand_tool_group",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({ tool_group: stringValue }, ["tool_group"]),
  },
  {
    name: "query_user_data",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters(
      {
        scope: stringValue,
        record_id: stringValue,
        exercise_id: stringValue,
        program_id: stringValue,
        session_id: stringValue,
        limit: integerValue,
        date_from: stringValue,
        date_to: stringValue,
        group_by: stringValue,
        metric: stringValue,
        query: stringValue,
        sort: stringValue,
        cursor: stringValue,
        projection: stringValue,
        fields: { type: "array", items: stringValue },
      },
      ["scope"],
    ),
  },
  {
    name: "mutate_user_data",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        operation: stringValue,
        record_type: stringValue,
        record_id: stringValue,
        payload: mutationPayload,
      },
      ["operation", "record_type"],
    ),
  },
  {
    name: "list_exercise_names",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters({}),
  },
  {
    name: "list_training_programs",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters({}),
  },
  {
    name: "get_training_program",
    schemaVersion: 1,
    mutation: false,
    parameters: parameters({ program_id: stringValue }, ["program_id"]),
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
    schemaVersion: 2,
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
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ gym_name: stringValue }, ["gym_name"]),
  },
  {
    name: "create_training_program",
    schemaVersion: 2,
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
    schemaVersion: 2,
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
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ program_id: stringValue }, ["program_id"]),
  },
  {
    name: "delete_training_program",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ program_id: stringValue }, ["program_id"]),
  },
  {
    name: "start_guided_workout",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        program_id: stringValue,
        auto_recording_policy: stringValue,
      },
      ["program_id"],
    ),
  },
  {
    name: "record_performance_analysis",
    schemaVersion: 2,
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
  {
    name: "submit_feedback",
    description:
      "只有用户当前消息明确要求向 Soma 维护者提交产品反馈时调用；设备发送当前消息原文和当前附件，不用于训练或身体反馈。",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({}),
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
    (definition.schemaVersion !== input.schemaVersion && input.schemaVersion !== 1) ||
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
