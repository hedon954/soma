import { ProtocolError } from "./domain.js";
import type { AgentEvent } from "./domain.js";

export interface DeviceToolDefinition {
  name: string;
  description?: string;
  schemaVersion: 1 | 2 | 3;
  mutation: boolean;
  parameters: {
    type: "object";
    properties: Record<string, Record<string, unknown>>;
    required?: string[];
    additionalProperties: false;
  };
}

export function effectiveAllowedDeviceTools(
  initial: string[],
  _events?: AgentEvent[],
): string[] {
  return [...new Set(initial)];
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
const templateExercisesV2 = {
  type: "array",
  items: {
    type: "object",
    properties: {
      exercise_id: integerValue,
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
const templateSetPrescriptionsV3 = {
  type: "array",
  items: {
    type: "object",
    properties: {
      order: { type: "integer", minimum: 1, maximum: 100 },
      kind: { type: "string", enum: ["warmup", "working"] },
      target_kind: { type: "string", enum: ["repetitions", "duration"] },
      target_reps: { type: "integer", minimum: 1, maximum: 1_000 },
      target_duration_seconds: { type: "integer", minimum: 1, maximum: 86_400 },
      target_weight_kg: { type: "number", minimum: 0, maximum: 1_000 },
      left_weight_kg: { type: "number", minimum: 0, maximum: 1_000 },
      right_weight_kg: { type: "number", minimum: 0, maximum: 1_000 },
      rest_between_sides_seconds: { type: "integer", minimum: 0, maximum: 3_600 },
      rest_after_set_seconds: { type: "integer", minimum: 0, maximum: 3_600 },
      notes: stringValue,
    },
    required: ["order", "kind", "target_kind"],
    additionalProperties: false,
  },
};
const templateExercisesV3 = {
  type: "array",
  items: {
    type: "object",
    properties: {
      exercise_id: { type: "integer", minimum: 1 },
      order: { type: "integer", minimum: 1, maximum: 100 },
      laterality: { type: "string", enum: ["none", "both", "left", "right"] },
      equipment_kind: stringValue,
      notes: stringValue,
      set_prescriptions: templateSetPrescriptionsV3,
    },
    required: ["exercise_id", "order", "laterality", "set_prescriptions"],
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
      total_sugar: numberValue,
    },
    required: ["name"],
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

function recordDomainDefinitions(): DeviceToolDefinition[] {
  const listParameters = parameters({
    date_from: stringValue,
    date_to: stringValue,
    sort: stringValue,
    limit: integerValue,
  });
  const recordIDParameters = parameters(
    { record_id: integerValue },
    ["record_id"],
  );
  const workoutProperties = {
    exercise_id: integerValue,
    occurred_at: stringValue,
    set_entries: setEntries,
    rest_seconds: integerValue,
    duration_minutes: integerValue,
    form_score: integerValue,
    intensity: stringValue,
    feedback: stringValue,
  };
  const mealProperties = {
    record_id: integerValue,
    occurred_at: stringValue,
    meal_type: stringValue,
    title: stringValue,
    calories: integerValue,
    protein: numberValue,
    carbs: numberValue,
    fat: numberValue,
    total_sugar: numberValue,
    glycemic_speed: { type: "string", enum: ["slow", "moderate", "fast"] },
    glycemic_assessment: stringValue,
    items: mealItems,
    note: stringValue,
  };
  const bodyProperties = {
    record_id: integerValue,
    occurred_at: stringValue,
    weight: numberValue,
    body_fat: numberValue,
    waist: numberValue,
    posture_note: stringValue,
    safety_note: stringValue,
  };
  return [
    { name: "list_workouts", schemaVersion: 2, mutation: false, parameters: listParameters },
    { name: "get_workout", schemaVersion: 2, mutation: false, parameters: recordIDParameters },
    {
      name: "create_workout",
      schemaVersion: 2,
      mutation: true,
      parameters: parameters(workoutProperties, ["exercise_id"]),
    },
    {
      name: "delete_workout",
      schemaVersion: 2,
      mutation: true,
      parameters: recordIDParameters,
    },
    { name: "list_meals", schemaVersion: 2, mutation: false, parameters: listParameters },
    { name: "get_meal", schemaVersion: 2, mutation: false, parameters: recordIDParameters },
    {
      name: "create_meal",
      schemaVersion: 2,
      mutation: true,
      parameters: parameters(
        Object.fromEntries(Object.entries(mealProperties).filter(([key]) => key !== "record_id")),
        ["title"],
      ),
    },
    { name: "delete_meal", schemaVersion: 2, mutation: true, parameters: recordIDParameters },
    {
      name: "list_body_entries",
      schemaVersion: 2,
      mutation: false,
      parameters: listParameters,
    },
    {
      name: "get_body_entry",
      schemaVersion: 2,
      mutation: false,
      parameters: recordIDParameters,
    },
    {
      name: "create_body_entry",
      schemaVersion: 2,
      mutation: true,
      parameters: parameters(
        Object.fromEntries(Object.entries(bodyProperties).filter(([key]) => key !== "record_id")),
      ),
    },
    {
      name: "delete_body_entry",
      schemaVersion: 2,
      mutation: true,
      parameters: recordIDParameters,
    },
  ];
}

const definitions: DeviceToolDefinition[] = [
  {
    name: "search_exercises",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({ query: stringValue, limit: integerValue }, ["query"]),
  },
  {
    name: "create_exercise",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ exercise_name: stringValue }, ["exercise_name"]),
  },
  {
    name: "create_exercise",
    schemaVersion: 3,
    mutation: true,
    parameters: parameters(
      {
        exercise_names: {
          type: "array",
          items: stringValue,
          minItems: 1,
          maxItems: 20,
        },
      },
      ["exercise_names"],
    ),
  },
  {
    name: "update_exercise",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      { exercise_id: integerValue, exercise_name: stringValue },
      ["exercise_id", "exercise_name"],
    ),
  },
  {
    name: "archive_exercise",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ exercise_id: integerValue }, ["exercise_id"]),
  },
  {
    name: "merge_exercises",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      { exercise_id: integerValue, target_exercise_id: integerValue },
      ["exercise_id", "target_exercise_id"],
    ),
  },
  ...recordDomainDefinitions(),
  {
    name: "create_workout",
    schemaVersion: 3,
    mutation: true,
    parameters: parameters(
      {
        workouts: {
          type: "array",
          minItems: 1,
          maxItems: 20,
          items: {
            type: "object",
            properties: {
              exercise_id: integerValue,
              occurred_at: stringValue,
              set_entries: setEntries,
              rest_seconds: integerValue,
              duration_minutes: integerValue,
              form_score: integerValue,
              intensity: stringValue,
              feedback: stringValue,
            },
            required: ["exercise_id"],
            additionalProperties: false,
          },
        },
      },
      ["workouts"],
    ),
  },
  {
    name: "list_programs",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({}),
  },
  {
    name: "get_program",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({ program_id: integerValue }, ["program_id"]),
  },
  {
    name: "create_program",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        program_name: stringValue,
        goal: stringValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercisesV2,
      },
      ["program_name", "template_name", "template_exercises"],
    ),
  },
  {
    name: "create_program_version",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        program_id: integerValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercisesV2,
      },
      ["program_id", "template_name", "template_exercises"],
    ),
  },
  {
    name: "get_program",
    schemaVersion: 3,
    mutation: false,
    parameters: parameters(
      { program_id: { type: "integer", minimum: 1 } },
      ["program_id"],
    ),
  },
  {
    name: "create_program",
    schemaVersion: 3,
    mutation: true,
    parameters: parameters(
      {
        program_name: stringValue,
        overview: stringValue,
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercisesV3,
      },
      ["program_name", "template_name", "template_exercises"],
    ),
  },
  {
    name: "create_program_version",
    schemaVersion: 3,
    mutation: true,
    parameters: parameters(
      {
        program_id: { type: "integer", minimum: 1 },
        template_name: stringValue,
        schedule_hint: stringValue,
        template_exercises: templateExercisesV3,
      },
      ["program_id", "template_name", "template_exercises"],
    ),
  },
  {
    name: "archive_program",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ program_id: integerValue }, ["program_id"]),
  },
  {
    name: "delete_program",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters({ program_id: integerValue }, ["program_id"]),
  },
  {
    name: "start_program",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      { program_id: integerValue, auto_recording_policy: stringValue },
      ["program_id"],
    ),
  },
  {
    name: "load_skill",
    schemaVersion: 2,
    mutation: false,
    parameters: parameters({ skill_id: stringValue }, ["skill_id"]),
  },
  {
    name: "update_workout",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        record_id: integerValue,
        occurred_at: stringValue,
        exercise_id: integerValue,
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
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        record_id: integerValue,
        occurred_at: stringValue,
        meal_type: stringValue,
        title: stringValue,
        calories: integerValue,
        protein: numberValue,
        carbs: numberValue,
        fat: numberValue,
        total_sugar: numberValue,
        glycemic_speed: { type: "string", enum: ["slow", "moderate", "fast"] },
        glycemic_assessment: stringValue,
        items: mealItems,
        note: stringValue,
      },
      ["record_id"],
    ),
  },
  {
    name: "update_body",
    schemaVersion: 2,
    mutation: true,
    parameters: parameters(
      {
        record_id: integerValue,
        occurred_at: stringValue,
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
export const deviceToolRegistryByVersion = new Map(
  definitions.map((definition) => [
    registryKey(definition.name, definition.schemaVersion),
    definition,
  ]),
);

export function validateDeviceTool(input: {
  name: string;
  schemaVersion: number;
  arguments: Record<string, unknown>;
  allowedNames: string[];
  parameters?: DeviceToolDefinition["parameters"];
}): DeviceToolDefinition {
  const definition = deviceToolRegistryByVersion.get(
    registryKey(input.name, input.schemaVersion),
  ) ?? (input.schemaVersion === 1
    ? deviceToolRegistry.get(input.name)
    : undefined);
  if (
    definition === undefined ||
    !input.allowedNames.includes(input.name)
  ) {
    throw new ProtocolError(
      "tool_schema_unsupported",
      "设备不支持该 Tool Schema。",
      409,
    );
  }
  validateSchema(input.arguments, definition.parameters, input.name);
  if (input.parameters !== undefined) {
    validateSchema(input.arguments, input.parameters, input.name);
  }
  if (input.schemaVersion === 3 && [
    "get_program", "create_program", "create_program_version",
  ].includes(input.name)) validatePlanV3(input);
  rejectForbiddenValues(input.arguments);
  return definition;
}

function registryKey(name: string, schemaVersion: number): string {
  return `${name}@${schemaVersion}`;
}

function validateSchema(
  value: unknown,
  schema: Record<string, unknown>,
  path: string,
): void {
  const type = schema.type;
  const expected = typeof type === "string"
    ? [type]
    : Array.isArray(type) && type.every((item) => typeof item === "string")
      ? type as string[]
      : [];
  if (expected.length > 0 && !expected.some((item) => matchesType(value, item))) {
    invalidSchema(`${path} 类型无效。`);
  }
  const allowed = schema.enum;
  if (Array.isArray(allowed) && !allowed.includes(value)) {
    invalidSchema(`${path} 枚举值无效。`);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) invalidSchema(`${path} 数值无效。`);
    if (typeof schema.minimum === "number" && value < schema.minimum) {
      invalidSchema(`${path} 小于允许范围。`);
    }
    if (typeof schema.maximum === "number" && value > schema.maximum) {
      invalidSchema(`${path} 超出允许范围。`);
    }
  }
  if (isObject(value) && expected.includes("object")) {
    const properties = isObject(schema.properties) ? schema.properties : {};
    const required = Array.isArray(schema.required)
      ? schema.required.filter((item): item is string => typeof item === "string")
      : [];
    const missing = required.find((key) => value[key] === undefined);
    if (missing !== undefined) invalidSchema(`${path}.${missing} 缺少必填字段。`);
    if (schema.additionalProperties === false) {
      const unknown = Object.keys(value).find((key) => properties[key] === undefined);
      if (unknown !== undefined) invalidSchema(`${path}.${unknown} 是未声明字段。`);
    }
    for (const [key, item] of Object.entries(value)) {
      const child = properties[key];
      if (isObject(child)) validateSchema(item, child, `${path}.${key}`);
    }
  }
  if (Array.isArray(value) && expected.includes("array")) {
    if (typeof schema.minItems === "number" && value.length < schema.minItems) {
      invalidSchema(`${path} 少于允许条数。`);
    }
    if (typeof schema.maxItems === "number" && value.length > schema.maxItems) {
      invalidSchema(`${path} 超过允许条数。`);
    }
    if (isObject(schema.items)) {
      value.forEach((item, index) =>
        validateSchema(item, schema.items as Record<string, unknown>, `${path}[${index}]`));
    }
  }
}

function matchesType(value: unknown, type: string): boolean {
  switch (type) {
    case "object": return isObject(value);
    case "array": return Array.isArray(value);
    case "string": return typeof value === "string";
    case "boolean": return typeof value === "boolean";
    case "integer": return typeof value === "number" && Number.isInteger(value);
    case "number": return typeof value === "number";
    case "null": return value === null;
    default: return false;
  }
}

function validatePlanV3(input: {
  name: string;
  arguments: Record<string, unknown>;
}): void {
  if (input.name === "get_program") {
    requireInteger(input.arguments.program_id, 1, Number.MAX_SAFE_INTEGER, "get_program.program_id");
    return;
  }
  if (input.name === "create_program_version") {
    requireInteger(
      input.arguments.program_id,
      1,
      Number.MAX_SAFE_INTEGER,
      "create_program_version.program_id",
    );
  }
  const exercises = input.arguments.template_exercises;
  if (!Array.isArray(exercises) || exercises.length < 1 || exercises.length > 100) {
    invalidSchema(`${input.name}.template_exercises 必须包含 1 到 100 个动作。`);
  }
  const exerciseOrders = new Set<number>();
  for (const [exerciseIndex, rawExercise] of exercises.entries()) {
    if (!isObject(rawExercise)) invalidSchema(`${input.name}.template_exercises[${exerciseIndex}] 无效。`);
    const exercise = rawExercise as Record<string, unknown>;
    const path = `${input.name}.template_exercises[${exerciseIndex}]`;
    requireInteger(exercise.exercise_id, 1, Number.MAX_SAFE_INTEGER, `${path}.exercise_id`);
    const order = requireInteger(exercise.order, 1, 100, `${path}.order`);
    if (exerciseOrders.has(order)) invalidSchema(`${path}.order 不能重复。`);
    exerciseOrders.add(order);
    const laterality = exercise.laterality;
    if (typeof laterality !== "string" || !["none", "both", "left", "right"].includes(laterality)) {
      invalidSchema(`${path}.laterality 无效。`);
    }
    const sets = exercise.set_prescriptions;
    if (!Array.isArray(sets) || sets.length < 1 || sets.length > 100) {
      invalidSchema(`${path}.set_prescriptions 必须包含 1 到 100 个组。`);
    }
    const setOrders = new Set<number>();
    for (const [setIndex, rawSet] of sets.entries()) {
      if (!isObject(rawSet)) invalidSchema(`${path}.set_prescriptions[${setIndex}] 无效。`);
      const set = rawSet as Record<string, unknown>;
      const setPath = `${path}.set_prescriptions[${setIndex}]`;
      const setOrder = requireInteger(set.order, 1, 100, `${setPath}.order`);
      if (setOrders.has(setOrder)) invalidSchema(`${setPath}.order 不能重复。`);
      setOrders.add(setOrder);
      if (set.target_kind === "repetitions") {
        requireInteger(set.target_reps, 1, 1_000, `${setPath}.target_reps`);
        if (set.target_duration_seconds !== undefined) {
          invalidSchema(`${setPath} 的次数和时长不能同时有效。`);
        }
      } else if (set.target_kind === "duration") {
        requireInteger(
          set.target_duration_seconds,
          1,
          86_400,
          `${setPath}.target_duration_seconds`,
        );
        if (set.target_reps !== undefined) {
          invalidSchema(`${setPath} 的次数和时长不能同时有效。`);
        }
      } else {
        invalidSchema(`${setPath}.target_kind 无效。`);
      }
      for (const key of ["target_weight_kg", "left_weight_kg", "right_weight_kg"]) {
        if (set[key] !== undefined) requireNumber(set[key], 0, 1_000, `${setPath}.${key}`);
      }
      for (const key of ["rest_between_sides_seconds", "rest_after_set_seconds"]) {
        if (set[key] !== undefined) requireInteger(set[key], 0, 3_600, `${setPath}.${key}`);
      }
      if (laterality !== "both" && set.rest_between_sides_seconds !== undefined) {
        invalidSchema(`${setPath}.rest_between_sides_seconds 只适用于 both。`);
      }
      if (laterality === "none" &&
          (set.left_weight_kg !== undefined || set.right_weight_kg !== undefined)) {
        invalidSchema(`${setPath} 的 none 不能设置逐侧重量。`);
      }
      if (laterality === "left" && set.right_weight_kg !== undefined) {
        invalidSchema(`${setPath} 的 left 不能设置右侧重量。`);
      }
      if (laterality === "right" && set.left_weight_kg !== undefined) {
        invalidSchema(`${setPath} 的 right 不能设置左侧重量。`);
      }
    }
  }
}

function requireInteger(
  value: unknown,
  minimum: number,
  maximum: number,
  path: string,
): number {
  if (typeof value !== "number" || !Number.isInteger(value) ||
      value < minimum || value > maximum) invalidSchema(`${path} 整数超出允许范围。`);
  return value as number;
}

function requireNumber(
  value: unknown,
  minimum: number,
  maximum: number,
  path: string,
): void {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < minimum || value > maximum) invalidSchema(`${path} 数值超出允许范围。`);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function invalidSchema(message: string): never {
  throw new ProtocolError(
    "tool_schema_unsupported",
    `Tool 参数不符合固定 Schema：${message}`,
    409,
  );
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
