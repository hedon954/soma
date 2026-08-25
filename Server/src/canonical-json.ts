export function canonicalJSON(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSON).join(",")}]`;
  }
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJSON(object[key])}`)
    .join(",")}}`;
}

export function sameToolRequest(
  lhs: {
    toolName: string;
    schemaVersion: number;
    mutation: boolean;
    arguments: unknown;
  },
  rhs: {
    toolName: string;
    schemaVersion: number;
    mutation: boolean;
    arguments: unknown;
  },
): boolean {
  return (
    lhs.toolName === rhs.toolName &&
    lhs.schemaVersion === rhs.schemaVersion &&
    lhs.mutation === rhs.mutation &&
    canonicalJSON(lhs.arguments) === canonicalJSON(rhs.arguments)
  );
}

