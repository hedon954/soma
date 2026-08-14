import { Client } from "pg";
import {
  applyMigrations,
  baselineInitialMigration,
  createMigration,
  loadMigrations,
  migrationStatus,
} from "./migrations.js";

async function main(): Promise<void> {
  const command = process.argv[2];
  if (command === "create") {
    const name = process.argv[3];
    if (name === undefined) {
      throw new Error("用法：npm run db:migrate:create -- <snake_case_name>");
    }
    const path = await createMigration(name);
    console.log(`已创建 ${path}`);
    return;
  }

  if (command !== "up" && command !== "status" && command !== "baseline") {
    throw new Error("Migration 命令必须是 create、status、up 或 baseline。");
  }

  const databaseURL = process.env.DATABASE_URL;
  if (databaseURL === undefined || databaseURL.length === 0) {
    throw new Error("缺少 DATABASE_URL；不会连接或修改数据库。");
  }

  const client = new Client({
    connectionString: databaseURL,
    ssl:
      process.env.NODE_ENV === "production"
        ? { rejectUnauthorized: true }
        : undefined,
  });
  await client.connect();

  try {
    if (command === "status") {
      const statuses = await migrationStatus(client);
      for (const status of statuses) {
        const suffix = status.appliedAt?.toISOString() ?? "pending";
        console.log(`${status.applied ? "applied" : "pending"} ${status.filename} ${suffix}`);
      }
      return;
    }

    if (command === "baseline") {
      const filename = process.argv[3];
      if (filename === undefined) {
        throw new Error(
          "用法：npm run db:migrate:baseline -- 001_initial.sql",
        );
      }
      await baselineInitialMigration(client, filename);
      console.log(`已将现有数据库 baseline 到 ${filename}。`);
      return;
    }

    const applied = await applyMigrations(client, undefined, (migration) => {
      console.log(`applied ${migration.filename}`);
    });
    if (applied.length === 0) {
      const migrations = await loadMigrations();
      console.log(`没有待执行 migration；当前共 ${migrations.length} 个。`);
    }
  } finally {
    await client.end();
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Migration 失败：${message}`);
  process.exitCode = 1;
});
