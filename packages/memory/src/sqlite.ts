import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import type { SessionCheckpoint } from "@continue/shared";
import { buildFtsMatchQuery, checkpointSearchDocument, normalizeSearchLimit } from "./retrieval";
import type { CheckpointSearchQuery, CheckpointStore } from "./types";

const MAX_RECENT_RESULTS = 1_000;

interface SqliteStatement {
  run(...parameters: unknown[]): unknown;
  all(...parameters: unknown[]): Array<Record<string, unknown>>;
  get(...parameters: unknown[]): Record<string, unknown> | undefined;
}

interface SqliteDatabase {
  exec(sql: string): void;
  prepare(sql: string): SqliteStatement;
  close(): void;
}

type DatabaseConstructor = new (path: string) => SqliteDatabase;

const sqliteGlobal = globalThis as typeof globalThis & {
  __continueMemoryDatabases?: Map<string, Promise<SqliteDatabase>>;
};
const databaseCache = sqliteGlobal.__continueMemoryDatabases ?? new Map();
sqliteGlobal.__continueMemoryDatabases = databaseCache;

function findRepositoryRoot(startPath: string): string {
  let currentPath = path.resolve(startPath);
  while (currentPath !== path.dirname(currentPath)) {
    if (fsSync.existsSync(path.join(currentPath, "pnpm-workspace.yaml"))) {
      return currentPath;
    }
    currentPath = path.dirname(currentPath);
  }
  return path.resolve(startPath);
}

function defaultDatabasePath(): string {
  const configuredPath = (
    process.env.CONTINUE_MEMORY_DATABASE_PATH
    ?? process.env.CONTINUE_MEMORY_PATH
  )?.trim();
  if (configuredPath) return path.resolve(configuredPath);
  return path.join(findRepositoryRoot(process.cwd()), "data/memory.sqlite");
}

function assertCheckpoint(value: unknown): asserts value is SessionCheckpoint {
  if (!value || typeof value !== "object") {
    throw new Error("Checkpoint must be an object");
  }
  const checkpoint = value as Partial<SessionCheckpoint>;
  const requiredStrings: Array<keyof SessionCheckpoint> = [
    "id", "endedAt", "project", "currentTask", "summary", "lastAction", "nextAction"
  ];
  for (const field of requiredStrings) {
    if (typeof checkpoint[field] !== "string" || checkpoint[field] === "") {
      throw new Error(`Checkpoint ${String(field)} must be a non-empty string`);
    }
  }
  if (Number.isNaN(Date.parse(checkpoint.endedAt!))) {
    throw new Error("Checkpoint endedAt must be a valid date");
  }
}

function decodeCheckpoint(row: Record<string, unknown>): SessionCheckpoint {
  const checkpoint = JSON.parse(String(row.memory_json)) as unknown;
  assertCheckpoint(checkpoint);
  return checkpoint;
}

function withTransaction<T>(database: SqliteDatabase, operation: () => T): T {
  database.exec("BEGIN IMMEDIATE");
  try {
    const result = operation();
    database.exec("COMMIT");
    return result;
  } catch (error) {
    try {
      database.exec("ROLLBACK");
    } catch {
    }
    throw error;
  }
}

function createSchema(database: SqliteDatabase) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS memories (
      id TEXT PRIMARY KEY,
      ended_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      memory_json TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS memories_ended_at_idx
      ON memories (ended_at DESC);
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_search USING fts5(
      checkpoint_id UNINDEXED,
      occurred_at,
      project,
      current_task,
      summary,
      last_action,
      next_action,
      key_activities
    );
  `);
}

function indexCheckpoint(database: SqliteDatabase, rowID: number, checkpoint: SessionCheckpoint) {
  const document = checkpointSearchDocument(checkpoint);
  database.prepare("DELETE FROM memory_search WHERE rowid = ?").run(rowID);
  database.prepare(`
    INSERT INTO memory_search (
      rowid, checkpoint_id, occurred_at, project, current_task,
      summary, last_action, next_action, key_activities
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    rowID,
    checkpoint.id,
    document.occurredAt,
    document.project,
    document.currentTask,
    document.summary,
    document.lastAction,
    document.nextAction,
    document.keyActivities
  );
}

async function migrateJson(database: SqliteDatabase, databasePath: string) {
  const jsonPath = path.join(path.dirname(databasePath), "checkpoints.json");
  let parsed: unknown;
  try {
    parsed = JSON.parse(await fs.readFile(jsonPath, "utf8")) as unknown;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw new Error(`Unable to migrate ${jsonPath}: ${(error as Error).message}`);
  }
  if (!Array.isArray(parsed)) {
    throw new Error(`Unable to migrate ${jsonPath}: expected an array of checkpoints`);
  }

  const insert = database.prepare(`
    INSERT OR IGNORE INTO memories (id, ended_at, created_at, memory_json)
    VALUES (?, ?, ?, ?)
  `);
  withTransaction(database, () => {
    for (const value of parsed) {
      assertCheckpoint(value);
      insert.run(value.id, value.endedAt, value.startedAt ?? value.endedAt, JSON.stringify(value));
    }
  });
}

function synchronizeSearchIndex(database: SqliteDatabase) {
  const rows = database.prepare(`
    SELECT m.rowid AS row_id, m.memory_json
    FROM memories AS m
    LEFT JOIN memory_search AS s ON s.rowid = m.rowid
    WHERE s.rowid IS NULL
  `).all();

  withTransaction(database, () => {
    database.exec("DELETE FROM memory_search WHERE rowid NOT IN (SELECT rowid FROM memories)");
    for (const row of rows) {
      indexCheckpoint(database, Number(row.row_id), decodeCheckpoint(row));
    }
  });
}

async function openDatabase(databasePath: string): Promise<SqliteDatabase> {
  await fs.mkdir(path.dirname(databasePath), { recursive: true });
  const sqlite = await import("node:sqlite") as unknown as { DatabaseSync: DatabaseConstructor };
  const database = new sqlite.DatabaseSync(databasePath);
  try {
    database.exec("PRAGMA busy_timeout = 5000");
    database.exec("PRAGMA journal_mode = WAL");
    database.exec("PRAGMA synchronous = NORMAL");
    createSchema(database);
    await migrateJson(database, databasePath);
    synchronizeSearchIndex(database);
    return database;
  } catch (error) {
    database.close();
    throw error;
  }
}

function cachedDatabase(databasePath: string): Promise<SqliteDatabase> {
  const resolvedPath = path.resolve(databasePath);
  const current = databaseCache.get(resolvedPath);
  if (current) return current;

  const created = openDatabase(resolvedPath).catch((error) => {
    if (databaseCache.get(resolvedPath) === created) databaseCache.delete(resolvedPath);
    throw error;
  });
  databaseCache.set(resolvedPath, created);
  return created;
}

function timeConditions(query: CheckpointSearchQuery, parameters: unknown[]) {
  const conditions: string[] = [];
  if (query.endedAfter) {
    conditions.push("m.ended_at >= ?");
    parameters.push(query.endedAfter);
  }
  if (query.endedBefore) {
    conditions.push("m.ended_at < ?");
    parameters.push(query.endedBefore);
  }
  return conditions;
}

export function createSqliteCheckpointStore(storagePath = defaultDatabasePath()): CheckpointStore {
  const resolvedPath = path.resolve(storagePath);
  const databasePromise = cachedDatabase(resolvedPath);

  return {
    async save(checkpoint): Promise<void> {
      assertCheckpoint(checkpoint);
      const database = await databasePromise;
      withTransaction(database, () => {
        database.prepare(`
          INSERT INTO memories (id, ended_at, created_at, memory_json)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            ended_at = excluded.ended_at,
            memory_json = excluded.memory_json
        `).run(
          checkpoint.id,
          checkpoint.endedAt,
          checkpoint.startedAt ?? checkpoint.endedAt,
          JSON.stringify(checkpoint)
        );
        const row = database.prepare("SELECT rowid FROM memories WHERE id = ?").get(checkpoint.id);
        if (!row) throw new Error(`SQLite did not return the saved checkpoint ${checkpoint.id}`);
        indexCheckpoint(database, Number(row.rowid), checkpoint);
      });
    },

    async getLatest(): Promise<SessionCheckpoint | null> {
      const database = await databasePromise;
      const row = database.prepare(`
        SELECT memory_json FROM memories
        ORDER BY ended_at DESC, rowid DESC LIMIT 1
      `).get();
      return row ? decodeCheckpoint(row) : null;
    },

    async getRecent(limit): Promise<SessionCheckpoint[]> {
      if (!Number.isFinite(limit) || limit <= 0) return [];
      const database = await databasePromise;
      const normalizedLimit = Math.min(MAX_RECENT_RESULTS, Math.floor(limit));
      return database.prepare(`
        SELECT memory_json FROM memories
        ORDER BY ended_at DESC, rowid DESC LIMIT ?
      `).all(normalizedLimit).map(decodeCheckpoint);
    },

    async getById(id): Promise<SessionCheckpoint | null> {
      if (!id) return null;
      const database = await databasePromise;
      const row = database.prepare("SELECT memory_json FROM memories WHERE id = ?").get(id);
      return row ? decodeCheckpoint(row) : null;
    },

    async search(query): Promise<SessionCheckpoint[]> {
      const limit = normalizeSearchLimit(query.limit);
      if (limit === 0) return [];
      const database = await databasePromise;
      const match = buildFtsMatchQuery(query.text);
      const parameters: unknown[] = [];
      const conditions = timeConditions(query, parameters);

      if (match) {
        conditions.unshift("memory_search MATCH ?");
        parameters.unshift(match);
        parameters.push(limit);
        return database.prepare(`
          SELECT m.memory_json
          FROM memory_search
          JOIN memories AS m ON m.rowid = memory_search.rowid
          WHERE ${conditions.join(" AND ")}
          ORDER BY bm25(memory_search, 0.0, 1.0, 8.0, 6.0, 3.0, 4.0, 4.0, 2.0),
                   m.ended_at DESC, m.rowid DESC
          LIMIT ?
        `).all(...parameters).map(decodeCheckpoint);
      }

      parameters.push(limit);
      return database.prepare(`
        SELECT m.memory_json
        FROM memories AS m
        ${conditions.length ? `WHERE ${conditions.join(" AND ")}` : ""}
        ORDER BY m.ended_at DESC, m.rowid DESC
        LIMIT ?
      `).all(...parameters).map(decodeCheckpoint);
    },

    async close(): Promise<void> {
      const cached = databaseCache.get(resolvedPath);
      if (!cached || cached !== databasePromise) return;
      const database = await cached;
      database.close();
      databaseCache.delete(resolvedPath);
    }
  };
}
