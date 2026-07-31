import type { TemporaryObjectStore } from "./object-store.js";
import type { CleanupResult, SomaStore } from "./store.js";

export class RetentionCleaner {
  constructor(
    private readonly store: SomaStore,
    private readonly objects: TemporaryObjectStore,
  ) {}

  async run(now = new Date()): Promise<CleanupResult> {
    const result = await this.store.cleanup(now);
    if (result.objectKeys.length > 0) {
      await this.objects.deleteObjects(result.objectKeys);
    }
    return result;
  }
}
