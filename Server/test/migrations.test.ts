import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import {
  createMigration,
  createdTableNames,
  loadMigrations,
  migrationChecksum,
  migrationRegistryFilename,
  sqlWithoutTransactionEnvelope,
} from "../src/migrations.js";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true })
    ),
  );
});

test("migration discovery orders versions and verifies naming", async () => {
  const directory = await makeMigrationDirectory();
  await writeFile(join(directory, "002_add_events.sql"), "SELECT 2;\n");
  await writeFile(join(directory, "001_initial.sql"), "SELECT 1;\n");

  const migrations = await loadMigrations(directory);
  assert.deepEqual(
    migrations.map((migration) => migration.filename),
    ["001_initial.sql", "002_add_events.sql"],
  );
  assert.equal(migrations[0]?.checksum, migrationChecksum("SELECT 1;\n"));

  await writeFile(join(directory, "003-bad-name.sql"), "SELECT 3;\n");
  await assert.rejects(loadMigrations(directory), /文件名不合法/);
});

test("migration discovery rejects gaps in the immutable sequence", async () => {
  const directory = await makeMigrationDirectory();
  await writeFile(join(directory, "001_initial.sql"), "SELECT 1;\n");
  await writeFile(join(directory, "003_add_events.sql"), "SELECT 3;\n");

  await assert.rejects(loadMigrations(directory), /缺少 002/);
});

test("migration creator appends the next immutable sequence", async () => {
  const directory = await makeMigrationDirectory();
  await writeFile(join(directory, "001_initial.sql"), "SELECT 1;\n");

  const path = await createMigration("add_training_index", directory);
  assert.equal(path, join(directory, "002_add_training_index.sql"));
  assert.match(await readFile(path, "utf8"), /^BEGIN;/);
  await assert.rejects(
    createMigration("Bad-Name", directory),
    /小写 snake_case/,
  );
});

test("transaction envelope is removed before atomic runner execution", () => {
  const sql = "BEGIN;\n\nCREATE TABLE example (id UUID);\n\nCOMMIT;\n";
  assert.equal(
    sqlWithoutTransactionEnvelope(sql),
    "CREATE TABLE example (id UUID);",
  );
  assert.deepEqual(createdTableNames(sql), ["example"]);
});

async function makeMigrationDirectory(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "soma-migrations-"));
  temporaryDirectories.push(directory);
  await writeFile(
    join(directory, migrationRegistryFilename),
    "CREATE TABLE soma_schema_migrations (filename TEXT PRIMARY KEY);\n",
  );
  return directory;
}
