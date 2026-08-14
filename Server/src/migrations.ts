import { createHash } from "node:crypto";
import {
  readdir,
  readFile,
  writeFile,
} from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Client, PoolClient } from "pg";

export const migrationDirectory = fileURLToPath(
  new URL("../migrations", import.meta.url),
);
export const migrationRegistryFilename = "000_schema_migrations.sql";

const migrationFilenamePattern = /^(\d{3,})_([a-z0-9]+(?:_[a-z0-9]+)*)\.sql$/;
const migrationLockKey = 1_397_704_739;
type MigrationClient = Client | PoolClient;

export interface MigrationFile {
  filename: string;
  version: number;
  checksum: string;
  sql: string;
}

export interface MigrationStatus extends MigrationFile {
  applied: boolean;
  appliedAt?: Date;
}

interface AppliedMigrationRow {
  filename: string;
  checksum: string;
  applied_at: Date;
}

export async function loadMigrations(
  directory = migrationDirectory,
): Promise<MigrationFile[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const migrations: MigrationFile[] = [];
  const versions = new Map<number, string>();

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".sql")) {
      continue;
    }
    if (entry.name === migrationRegistryFilename) {
      continue;
    }

    const match = migrationFilenamePattern.exec(entry.name);
    if (match === null) {
      throw new Error(
        `Migration 文件名不合法：${entry.name}，应为 001_snake_case.sql。`,
      );
    }

    const versionText = match[1];
    if (versionText === undefined) {
      throw new Error(`无法读取 migration 版本：${entry.name}`);
    }
    const version = Number.parseInt(versionText, 10);
    if (version === 0) {
      throw new Error("版本 000 只保留给 migration registry。 ");
    }
    const duplicate = versions.get(version);
    if (duplicate !== undefined) {
      throw new Error(
        `Migration 版本重复：${duplicate} 与 ${entry.name}。`,
      );
    }
    versions.set(version, entry.name);

    const sql = await readFile(join(directory, entry.name), "utf8");
    migrations.push({
      filename: entry.name,
      version,
      checksum: migrationChecksum(sql),
      sql,
    });
  }

  migrations.sort((left, right) => left.version - right.version);
  for (const [index, migration] of migrations.entries()) {
    const expectedVersion = index + 1;
    if (migration.version !== expectedVersion) {
      throw new Error(
        `Migration 版本必须连续：缺少 ${expectedVersion.toString().padStart(3, "0")}。`,
      );
    }
  }
  return migrations;
}

export function migrationChecksum(sql: string): string {
  return createHash("sha256").update(sql).digest("hex");
}

export function sqlWithoutTransactionEnvelope(sql: string): string {
  const envelope = sql.match(/^\s*BEGIN\s*;([\s\S]*?)COMMIT\s*;\s*$/i);
  return envelope?.[1]?.trim() ?? sql.trim();
}

export async function createMigration(
  name: string,
  directory = migrationDirectory,
): Promise<string> {
  if (!/^[a-z0-9]+(?:_[a-z0-9]+)*$/.test(name)) {
    throw new Error("Migration 名称必须使用小写 snake_case。");
  }

  const migrations = await loadMigrations(directory);
  const nextVersion = (migrations.at(-1)?.version ?? 0) + 1;
  const filename = `${nextVersion.toString().padStart(3, "0")}_${name}.sql`;
  const path = join(directory, filename);
  const template = `BEGIN;\n\n-- 只编写向前迁移；已经执行的 migration 不得修改。\n\nCOMMIT;\n`;
  await writeFile(path, template, { encoding: "utf8", flag: "wx" });
  return path;
}

export async function migrationStatus(
  client: MigrationClient,
  directory = migrationDirectory,
): Promise<MigrationStatus[]> {
  const migrations = await loadMigrations(directory);
  const registry = await client.query<{ registry: string | null }>(
    "SELECT to_regclass('public.soma_schema_migrations')::text AS registry",
  );
  if (registry.rows[0]?.registry === null) {
    return migrations.map((migration) => ({ ...migration, applied: false }));
  }

  const applied = await readAppliedMigrations(client);
  validateAppliedHistory(migrations, applied);
  return migrations.map((migration) => {
    const record = applied.get(migration.filename);
    return record === undefined
      ? { ...migration, applied: false }
      : { ...migration, applied: true, appliedAt: record.applied_at };
  });
}

export async function applyMigrations(
  client: MigrationClient,
  directory = migrationDirectory,
  onApplied: (migration: MigrationFile) => void = () => {},
): Promise<MigrationFile[]> {
  const migrations = await loadMigrations(directory);
  const appliedNow: MigrationFile[] = [];

  await client.query("SELECT pg_advisory_lock($1)", [migrationLockKey]);
  try {
    await ensureMigrationRegistry(client, directory);
    const applied = await readAppliedMigrations(client);
    validateAppliedHistory(migrations, applied);

    for (const migration of migrations) {
      if (applied.has(migration.filename)) {
        continue;
      }

      await client.query("BEGIN");
      try {
        await client.query(sqlWithoutTransactionEnvelope(migration.sql));
        await client.query(
          `INSERT INTO soma_schema_migrations (filename, checksum)
           VALUES ($1, $2)`,
          [migration.filename, migration.checksum],
        );
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }

      appliedNow.push(migration);
      onApplied(migration);
    }
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [migrationLockKey]);
  }

  return appliedNow;
}

export async function baselineInitialMigration(
  client: MigrationClient,
  filename: string,
  directory = migrationDirectory,
): Promise<void> {
  const migrations = await loadMigrations(directory);
  const initial = migrations[0];
  if (initial === undefined || filename !== initial.filename) {
    throw new Error(
      `Baseline 只允许最早的 migration：${initial?.filename ?? "不存在"}。`,
    );
  }

  await client.query("SELECT pg_advisory_lock($1)", [migrationLockKey]);
  try {
    await ensureMigrationRegistry(client, directory);
    const applied = await readAppliedMigrations(client);
    if (applied.size > 0) {
      throw new Error("Migration registry 已有记录，不能再次 baseline。");
    }

    const requiredTables = createdTableNames(initial.sql);
    for (const table of requiredTables) {
      const result = await client.query<{ relation: string | null }>(
        "SELECT to_regclass($1)::text AS relation",
        [`public.${table}`],
      );
      if (result.rows[0]?.relation === null) {
        throw new Error(`不能 baseline：现有数据库缺少表 ${table}。`);
      }
    }

    await client.query(
      `INSERT INTO soma_schema_migrations (filename, checksum)
       VALUES ($1, $2)`,
      [initial.filename, initial.checksum],
    );
  } finally {
    await client.query("SELECT pg_advisory_unlock($1)", [migrationLockKey]);
  }
}

export function createdTableNames(sql: string): string[] {
  return Array.from(
    sql.matchAll(
      /CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-z_][a-z0-9_]*)/gi,
    ),
    (match) => match[1],
  ).filter((name): name is string => name !== undefined);
}

async function ensureMigrationRegistry(
  client: MigrationClient,
  directory: string,
): Promise<void> {
  const sql = await readFile(
    join(directory, migrationRegistryFilename),
    "utf8",
  );
  await client.query(sql);
}

async function readAppliedMigrations(
  client: MigrationClient,
): Promise<Map<string, AppliedMigrationRow>> {
  const result = await client.query<AppliedMigrationRow>(
    `SELECT filename, checksum, applied_at
     FROM soma_schema_migrations
     ORDER BY filename`,
  );
  return new Map(result.rows.map((row) => [row.filename, row]));
}

function validateAppliedHistory(
  migrations: MigrationFile[],
  applied: Map<string, AppliedMigrationRow>,
): void {
  const current = new Map(
    migrations.map((migration) => [migration.filename, migration]),
  );

  for (const record of applied.values()) {
    const migration = current.get(record.filename);
    if (migration === undefined) {
      throw new Error(
        `已执行的 migration 已从仓库删除：${record.filename}。`,
      );
    }
    if (migration.checksum !== record.checksum) {
      throw new Error(
        `已执行的 migration 被修改：${record.filename}。请新增 migration。`,
      );
    }
  }

  let foundPending = false;
  for (const migration of migrations) {
    if (!applied.has(migration.filename)) {
      foundPending = true;
    } else if (foundPending) {
      throw new Error(
        `Migration 历史不是连续前缀：${migration.filename} 已执行，但更早版本仍为 pending。`,
      );
    }
  }
}
