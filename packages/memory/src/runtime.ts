import fs from "node:fs/promises";
import path from "node:path";
import {
  DEFAULT_ACTIVITY_TRACKING_POLICY,
  type ActivityTrackingPolicy,
  type RuntimeStatusRecord
} from "@continue/shared";
import type { RuntimeCoordinatorStore } from "./types";

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

const OBSERVATION_WINDOWS = [5, 15, 30, 60] as const;
const CHECKPOINT_RETENTION_DAYS = [1, 7, 30] as const;
const SCREENPIPE_RETENTION_DAYS = [0, 1, 7, 30] as const;
const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1000;

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
    CREATE TABLE IF NOT EXISTS runtime_policy (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      policy_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS runtime_state (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      phase TEXT NOT NULL,
      capture_status TEXT NOT NULL,
      status_message TEXT NOT NULL,
      last_activity_at TEXT,
      heartbeat_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS runtime_commands (
      id TEXT PRIMARY KEY,
      command TEXT NOT NULL,
      created_at TEXT NOT NULL,
      handled_at TEXT
    );
  `);
  return database;
}

function defaultPolicy(): ActivityTrackingPolicy {
  return {
    ...DEFAULT_ACTIVITY_TRACKING_POLICY,
    schedule: { ...DEFAULT_ACTIVITY_TRACKING_POLICY.schedule },
    excludedApplications: [...DEFAULT_ACTIVITY_TRACKING_POLICY.excludedApplications]
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function clampInteger(value: unknown, fallback: number, minimum: number, maximum: number): number {
  if (!isFiniteNumber(value)) return fallback;
  return Math.min(Math.max(Math.trunc(value), minimum), maximum);
}

function nearestObservationWindow(value: unknown, fallback: number): number {
  if (!isFiniteNumber(value)) return fallback;

  return OBSERVATION_WINDOWS.reduce((nearest, option) => {
    const nearestDistance = Math.abs(nearest - value);
    const optionDistance = Math.abs(option - value);
    return optionDistance < nearestDistance ? option : nearest;
  }, OBSERVATION_WINDOWS[0]);
}

function allowedInteger(value: unknown, options: readonly number[], fallback: number): number {
  return isFiniteNumber(value) && Number.isInteger(value) && options.includes(value) ? value : fallback;
}

function normalizedExclusions(value: unknown): string[] {
  if (!Array.isArray(value)) return defaultPolicy().excludedApplications;

  const seen = new Set<string>();
  const applications: string[] = [];
  for (const application of value) {
    if (typeof application !== "string") continue;

    const normalized = application.trim();
    if (!normalized) continue;

    const key = normalized.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    applications.push(normalized);
  }
  return applications;
}

function sanitizePolicy(value: unknown): ActivityTrackingPolicy {
  const source = isRecord(value) ? value : {};
  const schedule = isRecord(source.schedule) ? source.schedule : {};
  const defaults = DEFAULT_ACTIVITY_TRACKING_POLICY;

  const checkpointTrigger =
    source.checkpointTrigger === "automatic" ||
    source.checkpointTrigger === "manual" ||
    source.checkpointTrigger === "automaticAndManual"
      ? source.checkpointTrigger
      : defaults.checkpointTrigger;

  return {
    captureEnabled: typeof source.captureEnabled === "boolean" ? source.captureEnabled : defaults.captureEnabled,
    summariesEnabled: typeof source.summariesEnabled === "boolean" ? source.summariesEnabled : defaults.summariesEnabled,
    checkpointTrigger,
    idleThresholdMinutes: clampInteger(
      source.idleThresholdMinutes,
      defaults.idleThresholdMinutes,
      1,
      60
    ),
    observationWindowMinutes: nearestObservationWindow(
      source.observationWindowMinutes,
      defaults.observationWindowMinutes
    ),
    schedule: {
      isEnabled: typeof schedule.isEnabled === "boolean" ? schedule.isEnabled : defaults.schedule.isEnabled,
      startHour: clampInteger(schedule.startHour, defaults.schedule.startHour, 0, 23),
      endHour: clampInteger(schedule.endHour, defaults.schedule.endHour, 0, 23)
    },
    excludedApplications: normalizedExclusions(source.excludedApplications),
    checkpointRetentionDays: allowedInteger(
      source.checkpointRetentionDays,
      CHECKPOINT_RETENTION_DAYS,
      defaults.checkpointRetentionDays
    ),
    screenpipeRetentionDays: allowedInteger(
      source.screenpipeRetentionDays,
      SCREENPIPE_RETENTION_DAYS,
      defaults.screenpipeRetentionDays
    )
  };
}

function parsePolicy(policyJson: unknown): ActivityTrackingPolicy {
  if (typeof policyJson !== "string") return defaultPolicy();

  try {
    return sanitizePolicy(JSON.parse(policyJson) as unknown);
  } catch {
    return defaultPolicy();
  }
}

function resolveDatabasePath(storagePath?: string): Promise<string> {
  const configuredPath = process.env.CONTINUE_MEMORY_DATABASE_PATH?.trim();
  const selectedPath = storagePath ?? configuredPath;
  if (selectedPath) {
    return Promise.resolve(path.resolve(selectedPath));
  }

  return findWorkspaceRoot(process.cwd()).then((rootPath) => path.join(rootPath, "data/memory.sqlite"));
}

export function createSqliteRuntimeStore(storagePath?: string): RuntimeCoordinatorStore {
  const databasePromise = resolveDatabasePath(storagePath).then((databasePath) => loadDatabase(databasePath));

  return {
    getPolicy: async () => {
      const database = await databasePromise;
      const row = database.prepare("SELECT policy_json FROM runtime_policy WHERE singleton = 1").get();
      if (!row || row.policy_json === null || row.policy_json === undefined) return null;
      return parsePolicy(row.policy_json);
    },

    publishState: async (state: RuntimeStatusRecord) => {
      const database = await databasePromise;
      database.prepare(
        `INSERT INTO runtime_state (
           singleton, phase, capture_status, status_message, last_activity_at, heartbeat_at
         ) VALUES (1, ?, ?, ?, ?, ?)
         ON CONFLICT(singleton) DO UPDATE SET
           phase = excluded.phase,
           capture_status = excluded.capture_status,
           status_message = excluded.status_message,
           last_activity_at = excluded.last_activity_at,
           heartbeat_at = excluded.heartbeat_at`
      ).run(
        state.phase,
        state.captureStatus,
        state.statusMessage,
        state.lastActivityAt,
        state.heartbeatAt
      );
    },

    consumeManualAwayRequests: async () => {
      const database = await databasePromise;
      database.exec("BEGIN IMMEDIATE");
      try {
        const row = database.prepare(
          "SELECT COUNT(*) AS count FROM runtime_commands WHERE command = ? AND handled_at IS NULL"
        ).get("manual_away");
        const count = Math.max(0, Number(row?.count ?? 0));

        if (count > 0) {
          database.prepare(
            "UPDATE runtime_commands SET handled_at = ? WHERE command = ? AND handled_at IS NULL"
          ).run(new Date().toISOString(), "manual_away");
        }

        database.exec("COMMIT");
        return count;
      } catch (error) {
        try {
          database.exec("ROLLBACK");
        } catch {
          // Preserve the original SQLite error if rollback is unavailable.
        }
        throw error;
      }
    },

    pruneCheckpoints: async (retentionDays: number) => {
      const database = await databasePromise;
      const memoriesTable = database.prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memories'"
      ).get();
      if (!memoriesTable) return;

      const normalizedRetention = CHECKPOINT_RETENTION_DAYS.includes(
        retentionDays as (typeof CHECKPOINT_RETENTION_DAYS)[number]
      ) ? retentionDays : DEFAULT_ACTIVITY_TRACKING_POLICY.checkpointRetentionDays;
      const cutoff = new Date(Date.now() - normalizedRetention * DAY_IN_MILLISECONDS).toISOString();
      database.prepare("DELETE FROM memories WHERE julianday(ended_at) < julianday(?)").run(cutoff);
    }
  };
}
