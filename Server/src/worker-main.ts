import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import {
  ActivityPushProjector,
  AppleAPNsProvider,
  NoopAPNsProvider,
  OutboxDispatcher,
} from "./apns.js";
import { RetentionCleaner } from "./cleanup.js";
import { S3TemporaryObjectStore } from "./object-store.js";
import {
  logEvent,
  logOperationalError,
} from "./operational-log.js";
import { PostgresSomaStore } from "./postgres-store.js";
import {
  explicitCapabilityFlag,
  OpenAICompatibleManagedProvider,
  parseProviderExtraConfig,
} from "./provider.js";
import { TokenCipher } from "./security.js";
import { AgentWorker } from "./worker.js";

const databaseURL = requiredEnvironment("DATABASE_URL");
const store = new PostgresSomaStore(
  new Pool({
    connectionString: databaseURL,
    max: 5,
    ssl:
      process.env.NODE_ENV === "production"
        ? { rejectUnauthorized: true }
        : undefined,
  }),
);
const provider = new OpenAICompatibleManagedProvider(
  requiredEnvironment("SOMA_PROVIDER_BASE_URL"),
  requiredEnvironment("SOMA_PROVIDER_API_KEY"),
  requiredEnvironment("SOMA_PROVIDER_MODEL"),
  undefined,
  undefined,
  explicitCapabilityFlag(process.env.SOMA_PROVIDER_SUPPORTS_DIRECT_VIDEO),
  parseProviderExtraConfig(process.env.SOMA_PROVIDER_EXTRA_CONFIG),
);
const objects = new S3TemporaryObjectStore(
  requiredEnvironment("SOMA_OBJECT_BUCKET"),
  {
    region: requiredEnvironment("SOMA_OBJECT_REGION"),
    ...(process.env.SOMA_OBJECT_ENDPOINT === undefined
      ? {}
      : { endpoint: process.env.SOMA_OBJECT_ENDPOINT }),
  },
);
const worker = new AgentWorker(
  store,
  provider,
  `worker-${randomUUID()}`,
  30,
  {
    async resolve(job) {
      if (job.input === undefined || job.input.uploadIDs.length === 0) {
        return [];
      }
      const uploads = await store.getUploads(
        job.deviceID,
        job.input.uploadIDs,
      );
      const uploadsByID = new Map(uploads.map((upload) => [upload.id, upload]));
      const expiresAt = new Date(Date.now() + 15 * 60 * 1_000);
      return Promise.all(
        job.input.mediaBindings.map(async (binding) => {
          const upload = uploadsByID.get(binding.uploadID);
          if (upload === undefined || upload.completedAt === undefined) {
            throw new Error("任务媒体绑定引用了不可用的上传。");
          }
          return {
            id: binding.id,
            contentType: upload.contentType,
            url: await objects.createDownloadURL(
              upload.objectKey,
              expiresAt,
            ),
          };
        }),
      );
    },
  },
);
const cleaner = new RetentionCleaner(
  store,
  objects,
);
const apnsProvider =
  process.env.SOMA_APNS_PRIVATE_KEY === undefined
    ? new NoopAPNsProvider()
    : new AppleAPNsProvider(
        requiredEnvironment("SOMA_APNS_TEAM_ID"),
        requiredEnvironment("SOMA_APNS_KEY_ID"),
        process.env.SOMA_BUNDLE_ID ?? "top.hedon.soma",
        requiredEnvironment("SOMA_APNS_PRIVATE_KEY").replace(/\\n/g, "\n"),
      );
const outbox = new OutboxDispatcher(
  store,
  new ActivityPushProjector(
    store,
    apnsProvider,
    new TokenCipher(requiredEnvironment("SOMA_TOKEN_ENCRYPTION_KEY")),
  ),
);

async function run(): Promise<void> {
  let nextCleanupAt = Date.now();
  for (;;) {
    let job;
    let dispatched = 0;
    try {
      job = await worker.runOnce();
    } catch (error) {
      logOperationalError("worker_iteration_failed", error);
    }
    try {
      dispatched = await outbox.runBatch();
    } catch (error) {
      logOperationalError("outbox_dispatch_failed", error);
    }
    if (job === undefined && dispatched === 0) {
      await store.waitForJobSignal(30_000);
    }
    if (Date.now() >= nextCleanupAt) {
      try {
        const result = await cleaner.run();
        logEvent("retention_cleanup_completed", {
          expiredJobs: result.expiredJobIDs.length,
          deletedContentJobs: result.deletedContentJobIDs.length,
          deletedMetadataJobs: result.deletedMetadataJobIDs.length,
          deletedObjects: result.objectKeys.length,
        });
      } catch (error) {
        logOperationalError("retention_cleanup_failed", error);
      }
      nextCleanupAt = Date.now() + 60_000;
    }
  }
}

await run();

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.length === 0) {
    throw new Error(`${name} is required`);
  }
  return value;
}
