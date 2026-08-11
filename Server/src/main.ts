import { randomBytes } from "node:crypto";
import { Pool } from "pg";
import { createSomaServer } from "./api.js";
import { GmailFeedbackEmailProvider } from "./feedback.js";
import { S3TemporaryObjectStore } from "./object-store.js";
import { logEvent } from "./operational-log.js";
import { PostgresSomaStore } from "./postgres-store.js";
import { supportsDirectVideo } from "./provider.js";
import {
  AllowDevelopmentAttestation,
  DeviceIdentityService,
  RequiredAppAttestAdapter,
  TokenCipher,
} from "./security.js";

const databaseURL = requiredEnvironment("DATABASE_URL");
const tokenSecret = requiredEnvironment("SOMA_TOKEN_SECRET");
const encryptionKey = requiredEnvironment("SOMA_TOKEN_ENCRYPTION_KEY");
const port = Number(process.env.PORT ?? "8080");
const pool = new Pool({
  connectionString: databaseURL,
  max: 10,
  ssl:
    process.env.NODE_ENV === "production"
      ? { rejectUnauthorized: true }
      : undefined,
});
const store = new PostgresSomaStore(pool);
const objectStore = new S3TemporaryObjectStore(
  requiredEnvironment("SOMA_OBJECT_BUCKET"),
  {
    region: requiredEnvironment("SOMA_OBJECT_REGION"),
    ...(process.env.SOMA_OBJECT_ENDPOINT === undefined
      ? {}
      : { endpoint: process.env.SOMA_OBJECT_ENDPOINT }),
  },
);
const attestation =
  process.env.NODE_ENV === "production"
    ? new RequiredAppAttestAdapter(async (input) => {
        const response = await fetch(
          requiredEnvironment("SOMA_APP_ATTEST_VERIFIER_URL"),
          {
            method: "POST",
            headers: {
              authorization:
                `Bearer ${requiredEnvironment("SOMA_APP_ATTEST_VERIFIER_TOKEN")}`,
              "content-type": "application/json",
            },
            body: JSON.stringify(input),
          },
        );
        if (!response.ok) return false;
        const result = (await response.json()) as { valid?: boolean };
        return result.valid === true;
      })
    : new AllowDevelopmentAttestation();
const identity = new DeviceIdentityService(
  store,
  tokenSecret,
  attestation,
);
const server = createSomaServer({
  store,
  identity,
  objects: objectStore,
  tokenCipher: new TokenCipher(encryptionKey),
  directVideoEnabled: supportsDirectVideo(process.env.SOMA_PROVIDER_MODEL ?? ""),
  feedback: new GmailFeedbackEmailProvider(
    requiredEnvironment("SOMA_FEEDBACK_GMAIL_CLIENT_ID"),
    requiredEnvironment("SOMA_FEEDBACK_GMAIL_CLIENT_SECRET"),
    requiredEnvironment("SOMA_FEEDBACK_GMAIL_REFRESH_TOKEN"),
  ),
});

server.listen(port, "0.0.0.0", () => {
  // No request body, token, IP, health data, or provider payload is logged.
  logEvent("server_started", {
    port,
    instanceID: randomBytes(8).toString("hex"),
  });
});

function requiredEnvironment(name: string): string {
  const value = process.env[name];
  if (value === undefined || value.length === 0) {
    throw new Error(`${name} is required`);
  }
  return value;
}
