import fs from "node:fs/promises";
import path from "node:path";
import type { SessionCheckpoint, SessionMemory } from "@continue/shared";
import type { CheckpointStore, MemoryQuery } from "./types";
import { searchMemory } from "./retrieval";

const MAX_MEMORY_ENTRIES = 100;

interface SqliteStatement {
  run(...parameters: unknown[]): void;
  all(...parameters: unknown[]): Array<Record<string, unknown>>;
  get(...parameters: unknown[]): Record<string, unknown> | undefined;
}

interface SqliteDatabase {
  exec(sql: string): void;
  prepare(sql: string): SqliteStatement;
  close(): void;
}

async function findWorkspaceRoot(startPath: string): Promise<string> {
  let currentPath = path.resolve(startPath);

  while (true) {
    try {
      await fs.access(path.join(currentPath, "pnpm-workspace.yaml"));
      return currentPath;
    } catch {
      const parentPath = path.dirname(currentPath);
      if (parentPath === currentPath) return path.resolve(startPath);
      currentPath = parentPath;
    }
  }
}

async function loadDatabase(databasePath: string): Promise<SqliteDatabase> {
  // Node 24 provides node:sqlite, while older installed Node typings do not declare it.
  const { DatabaseSync } = await import("node:sqlite");
  await fs.mkdir(path.dirname(databasePath), { recursive: true });
  const database = new DatabaseSync(databasePath) as SqliteDatabase;
  database.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS memories (
      id TEXT PRIMARY KEY,
      ended_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      memory_json TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS memories_ended_at_idx ON memories (ended_at DESC);
  `);
  return database;
}

async function migrateJsonIfPresent(database: SqliteDatabase, databasePath: string): Promise<void> {
  const count = database.prepare("SELECT COUNT(*) AS count FROM memories").get();
  if (Number(count?.count ?? 0) > 0) return;

  const jsonPath = path.join(path.dirname(databasePath), "checkpoints.json");
  try {
    const raw = await fs.readFile(jsonPath, "utf8");
    const checkpoints = JSON.parse(raw) as SessionCheckpoint[];
    if (!Array.isArray(checkpoints)) return;

    const insert = database.prepare(
      "INSERT OR IGNORE INTO memories (id, ended_at, created_at, memory_json) VALUES (?, ?, ?, ?)"
    );
    for (const checkpoint of checkpoints.slice(-MAX_MEMORY_ENTRIES)) {
      insert.run(
        checkpoint.id,
        checkpoint.endedAt,
        checkpoint.createdAt ?? checkpoint.endedAt,
        JSON.stringify(checkpoint)
      );
    }
  } catch {
    return;
  }
}

function normalizeMemory(memory: SessionMemory): SessionMemory {
  const timestamp = new Date().toISOString();
  return {
    ...memory,
    updatedAt: timestamp,
    tags: Array.from(new Set(memory.tags ?? [])),
    facts: Array.from(new Map((memory.facts ?? []).map((fact) => [`${fact.type}:${fact.value}`, fact])).values())
  };
}

function decodeRows(rows: Array<Record<string, unknown>>): SessionMemory[] {
  return rows.map((row) => JSON.parse(String(row.memory_json)) as SessionMemory);
}

export function createSqliteCheckpointStore(storagePath?: string): CheckpointStore {
  const configuredPath = process.env.CONTINUE_MEMORY_DATABASE_PATH?.trim();
  const selectedPath = storagePath ?? configuredPath;
  const databasePathPromise = selectedPath
    ? Promise.resolve(path.resolve(selectedPath))
    : findWorkspaceRoot(process.cwd()).then((rootPath) => path.join(rootPath, "data/memory.sqlite"));
  const databasePromise = databasePathPromise.then(async (databasePath) => {
    const database = await loadDatabase(databasePath);
    await migrateJsonIfPresent(database, databasePath);
    return database;
  });

  const saveMemory = async (memory: SessionMemory): Promise<void> => {
    const database = await databasePromise;
    const normalized = normalizeMemory(memory);
    database.prepare(
      `INSERT INTO memories (id, ended_at, created_at, memory_json)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET ended_at = excluded.ended_at, memory_json = excluded.memory_json`
    ).run(normalized.id, normalized.endedAt, normalized.createdAt ?? normalized.endedAt, JSON.stringify(normalized));
    database.exec(`
      DELETE FROM memories
      WHERE id NOT IN (SELECT id FROM memories ORDER BY ended_at DESC LIMIT ${MAX_MEMORY_ENTRIES});
    `);
  };

  return {
    save: saveMemory,
    getLatest: async () => {
      const database = await databasePromise;
      const row = database.prepare("SELECT memory_json FROM memories ORDER BY ended_at DESC, rowid DESC LIMIT 1").get();
      return row ? (JSON.parse(String(row.memory_json)) as SessionCheckpoint) : null;
    },
    getRecent: async (limit: number) => {
      if (limit <= 0) return [];
      const database = await databasePromise;
      const rows = database.prepare("SELECT memory_json FROM memories ORDER BY ended_at DESC, rowid DESC LIMIT ?").all(limit);
      return decodeRows(rows) as SessionCheckpoint[];
    },
    saveMemory,
    getLatestMemory: async () => {
      const database = await databasePromise;
      const row = database.prepare("SELECT memory_json FROM memories ORDER BY ended_at DESC, rowid DESC LIMIT 1").get();
      return row ? (JSON.parse(String(row.memory_json)) as SessionMemory) : null;
    },
    searchMemory: async (query: MemoryQuery) => {
      const database = await databasePromise;
      const rows = database.prepare("SELECT memory_json FROM memories ORDER BY ended_at DESC, rowid DESC").all();
      return searchMemory(decodeRows(rows), query);
    }
  };
}
