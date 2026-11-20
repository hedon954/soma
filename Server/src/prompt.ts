import { readFileSync } from "node:fs";

export function loadPrompt(name: string): string {
  return readFileSync(new URL(`./prompts/${name}.md`, import.meta.url), "utf8").replace(/\n$/, "");
}

export function renderPrompt(template: string, values: Record<string, string>): string {
  const used = new Set<string>();
  const result = template.replace(/\{\{([a-z][a-z0-9_]*)\}\}/g, (_, key: string) => {
    const value = values[key];
    if (value === undefined || !Object.hasOwn(values, key)) {
      throw new Error(`Missing prompt argument: ${key}`);
    }
    used.add(key);
    return value;
  });
  if (used.size !== Object.keys(values).length) {
    throw new Error("Unexpected prompt arguments");
  }
  return result;
}
