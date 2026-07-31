import { ProtocolError } from "./domain.js";

export function logEvent(
  event: string,
  fields: Record<string, string | number | boolean> = {},
): void {
  process.stdout.write(JSON.stringify({
    level: "info",
    event,
    ...fields,
  }) + "\n");
}

export function logOperationalError(event: string, error: unknown): void {
  process.stderr.write(JSON.stringify({
    level: "error",
    event,
    errorCategory:
      error instanceof ProtocolError
        ? error.code
        : error instanceof Error
          ? error.constructor.name
          : "unknown",
  }) + "\n");
}
