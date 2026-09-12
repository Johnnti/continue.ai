import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  getActivitySignal,
  isApplicationExcluded,
  isCaptureActive,
  isWithinTrackingSchedule,
  normalizeActivityTrackingPolicy,
  normalizeExcludedApplications,
  filterSummaryObservations,
  trimObservationsToWindow
} from "../apps/worker/src/activityPolicy";
import { runActivityProfile, type RuntimeStoreLike } from "../apps/worker/src/scheduler";
import { createSqliteRuntimeStore } from "../packages/memory/src/runtime";
import {
  DEFAULT_ACTIVITY_TRACKING_POLICY,
  type ActivityEvent,
  type ActivityTrackingPolicy,
  type RuntimeStatusRecord,
  type SessionCheckpoint
} from "../packages/shared/src/types";

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

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1000;
const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function run(command: string, arguments_: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, arguments_, {
      cwd: repositoryRoot,
      stdio: "inherit"
    });

    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(new Error(
        `${command} failed with ${signal ? `signal ${signal}` : `exit code ${code ?? "unknown"}`}`
      ));
    });
  });
}

function localDate(hour: number, minute = 0): Date {
  return new Date(2026, 0, 15, hour, minute, 0, 0);
}

function event(timestamp: string, fields: Omit<ActivityEvent, "timestamp"> = {}): ActivityEvent {
  return { timestamp, ...fields };
}

function verifyPolicyNormalization(): void {
  assert.deepEqual(normalizeActivityTrackingPolicy(), DEFAULT_ACTIVITY_TRACKING_POLICY);

  const invalid = normalizeActivityTrackingPolicy({
    checkpointTrigger: "not-a-trigger",
    idleThresholdMinutes: 0,
    observationWindowMinutes: Number.NaN,
    checkpointRetentionDays: -1,
    screenpipeRetentionDays: Number.POSITIVE_INFINITY,
    excludedApplications: [" Slack ", "slack", "", "Visual Studio Code", 42],
    schedule: {
      isEnabled: true,
      startHour: 99,
      endHour: -4
    }
  } as unknown as Parameters<typeof normalizeActivityTrackingPolicy>[0]);

  assert.equal(invalid.checkpointTrigger, DEFAULT_ACTIVITY_TRACKING_POLICY.checkpointTrigger);
  assert.equal(invalid.idleThresholdMinutes, 1);
  assert.equal(invalid.observationWindowMinutes, DEFAULT_ACTIVITY_TRACKING_POLICY.observationWindowMinutes);
  assert.equal(invalid.checkpointRetentionDays, DEFAULT_ACTIVITY_TRACKING_POLICY.checkpointRetentionDays);
  assert.equal(invalid.screenpipeRetentionDays, DEFAULT_ACTIVITY_TRACKING_POLICY.screenpipeRetentionDays);
  assert.deepEqual(invalid.excludedApplications, ["Slack", "Visual Studio Code"]);
  assert.deepEqual(invalid.schedule, {
    isEnabled: true,
    startHour: 23,
    endHour: 0
  });
}

function verifyScheduleAndCapture(): void {
  const normalSchedule = normalizeActivityTrackingPolicy({
    schedule: { isEnabled: true, startHour: 9, endHour: 17 }
  });
  assert.equal(isWithinTrackingSchedule(normalSchedule, localDate(9)), true);
  assert.equal(isWithinTrackingSchedule(normalSchedule, localDate(16, 59)), true);
  assert.equal(isWithinTrackingSchedule(normalSchedule, localDate(17)), false);
  assert.equal(isWithinTrackingSchedule(normalSchedule, localDate(8, 59)), false);

  const overnightSchedule = normalizeActivityTrackingPolicy({
    schedule: { isEnabled: true, startHour: 22, endHour: 6 }
  });
  assert.equal(isWithinTrackingSchedule(overnightSchedule, localDate(23)), true);
  assert.equal(isWithinTrackingSchedule(overnightSchedule, localDate(2)), true);
  assert.equal(isWithinTrackingSchedule(overnightSchedule, localDate(6)), false);
  assert.equal(isWithinTrackingSchedule(overnightSchedule, localDate(12)), false);

  const disabledCapture = normalizeActivityTrackingPolicy({
    captureEnabled: false,
    schedule: { isEnabled: false }
  });
  assert.equal(isCaptureActive(disabledCapture, localDate(12)), false);

  const scheduledCapture = normalizeActivityTrackingPolicy({
    captureEnabled: true,
    schedule: { isEnabled: true, startHour: 9, endHour: 17 }
  });
  assert.equal(isCaptureActive(scheduledCapture, localDate(12)), true);
  assert.equal(isCaptureActive(scheduledCapture, localDate(18)), false);
}

function verifyExclusions(): void {
  const excludedApplications = normalizeExcludedApplications([
    " Slack ",
    "slack",
    "Visual Studio Code",
    "SLACK",
    ""
  ]);

  assert.deepEqual(excludedApplications, ["Slack", "Visual Studio Code"]);
  assert.equal(isApplicationExcluded("  sLaCk ", excludedApplications), true);
  assert.equal(isApplicationExcluded("Visual Studio Code", excludedApplications), true);
  assert.equal(isApplicationExcluded("Slack Desktop", excludedApplications), false);
  assert.equal(isApplicationExcluded(undefined, excludedApplications), false);
}

function verifyActivitySignals(): void {
  const nativeSignal = getActivitySignal(
    event("2026-09-12T18:00:00.000Z", {
      appName: "Terminal",
      idleSeconds: 90
    }),
    event("2026-09-12T17:59:00.000Z", { appName: "Browser" }),
    null,
    4,
    new Date("2026-09-12T18:00:30.000Z")
  );
  assert.equal(nativeSignal.usedCaptureIdle, true);
  assert.equal(nativeSignal.presenceDetected, true);
  assert.equal(nativeSignal.idleSeconds, 90);
  assert.equal(nativeSignal.lastActivityAt, "2026-09-12T17:58:30.000Z");

  const fallbackSignal = getActivitySignal(
    event("2026-09-12T18:05:00.000Z", {
      appName: "Terminal",
      interactions: [{
        timestamp: "2026-09-12T18:05:00.000Z",
        type: "click",
        appName: "Terminal"
      }]
    }),
    event("2026-09-12T18:04:00.000Z", { appName: "Terminal" }),
    "2026-09-12T18:00:00.000Z",
    4,
    new Date("2026-09-12T18:05:30.000Z")
  );
  assert.equal(fallbackSignal.usedCaptureIdle, false);
  assert.equal(fallbackSignal.presenceDetected, true);
  assert.equal(fallbackSignal.idleSeconds, 0);
  assert.equal(fallbackSignal.lastActivityAt, "2026-09-12T18:05:00.000Z");
}

function verifyObservationAndSummaryFiltering(): void {
  const observations = [
    event("2026-09-12T12:00:00.000Z", { text: "old" }),
    event("2026-09-12T12:10:00.000Z", { text: "kept" }),
    event("not-a-timestamp", { text: "untimed" }),
    event("2026-09-12T12:20:00.000Z", { text: "newest" })
  ];
  assert.deepEqual(
    trimObservationsToWindow(observations, 15).map((observation) => observation.text),
    ["kept", "newest"]
  );

  const summaryObservations = [
    event("2026-09-12T12:00:00.000Z", { appName: "sLaCk", text: "excluded foreground" }),
    event("2026-09-12T12:01:00.000Z", { appName: "Slack Desktop", text: "exact match required" }),
    event("2026-09-12T12:02:00.000Z", {
      text: "mixed interactions",
      interactions: [
        { timestamp: "2026-09-12T12:02:00.000Z", type: "click", appName: "SLACK" },
        { timestamp: "2026-09-12T12:02:01.000Z", type: "scroll", appName: "Terminal" }
      ]
    }),
    event("2026-09-12T12:03:00.000Z", {
      text: "only excluded interaction",
      interactions: [
        { timestamp: "2026-09-12T12:03:00.000Z", type: "click", appName: "slack" }
      ]
    }),
    event("2026-09-12T12:04:00.000Z", { text: "no application" })
  ];
  const filtered = filterSummaryObservations(summaryObservations, ["Slack"]);

  assert.deepEqual(filtered.map((observation) => observation.text), [
    "exact match required",
    "mixed interactions",
    "no application"
  ]);
  assert.equal(filtered[1]?.interactions?.length, 1);
  assert.equal(filtered[1]?.interactions?.[0]?.appName, "Terminal");
}

function checkpointFor(events: ActivityEvent[]): SessionCheckpoint {
  const endedAt = events.at(-1)?.timestamp ?? "2026-09-12T18:00:00.000Z";
  return {
    id: `checkpoint-${endedAt}`,
    startedAt: events[0]?.timestamp,
    endedAt,
    project: "continue.ai",
    currentTask: "Verify the activity scheduler",
    summary: "A deterministic checkpoint generated by the runtime verification.",
    lastAction: "Detected an away transition",
    nextAction: "Notify after return activity",
    resumeTargets: [],
    confidence: 1,
    sourceWindowMinutes: 30,
    sourceEventCount: events.length
  };
}

function runtimeStoreFor(
  policy: ActivityTrackingPolicy,
  states: RuntimeStatusRecord[],
  manualResponses: number[] = []
): RuntimeStoreLike {
  return {
    getPolicy: () => policy,
    publishState: (state) => {
      states.push(state);
    },
    consumeManualAwayRequests: () => manualResponses.shift() ?? 0,
    pruneCheckpoints: () => undefined
  };
}

function scriptedCaptures(
  events: ActivityEvent[],
  setNow: (date: Date) => void
): { captures(): AsyncIterable<ActivityEvent> } {
  return {
    async *captures() {
      for (const capture of events) {
        setNow(new Date(capture.timestamp));
        yield capture;
      }
    }
  };
}

async function verifySchedulerTransitionsAndRetries(): Promise<void> {
  const policy = normalizeActivityTrackingPolicy({ idleThresholdMinutes: 1 });
  const captures = [
    event("2026-09-12T18:00:00.000Z", { appName: "Terminal", idleSeconds: 0 }),
    event("2026-09-12T18:01:00.000Z", { appName: "Terminal", idleSeconds: 60 }),
    event("2026-09-12T18:01:30.000Z", { appName: "Terminal", idleSeconds: 0 }),
    event("2026-09-12T18:02:31.000Z", { appName: "Terminal", idleSeconds: 0 })
  ];
  let currentTime = new Date(captures[0]!.timestamp);
  const states: RuntimeStatusRecord[] = [];
  const summarizedWindows: string[][] = [];
  const saved: SessionCheckpoint[] = [];
  let summaryAttempt = 0;

  await runActivityProfile({
    captureClient: scriptedCaptures(captures, (date) => {
      currentTime = date;
    }),
    checkpointStore: {
      save: (checkpoint) => {
        saved.push(checkpoint);
      }
    },
    runtimeStore: runtimeStoreFor(policy, states),
    now: () => currentTime,
    returningVisibilityMs: 60_000,
    summarize: async (events) => {
      summarizedWindows.push(events.map((item) => item.timestamp));
      summaryAttempt += 1;
      if (summaryAttempt === 1) {
        throw new Error("synthetic transient summarizer failure");
      }
      return checkpointFor(events);
    }
  });

  assert.equal(summaryAttempt, 2, "A failed checkpoint must retry once with the retained window");
  assert.deepEqual(summarizedWindows[1], summarizedWindows[0]);
  assert.equal(saved.length, 1, "One away episode must create exactly one durable checkpoint");
  const phases = states.map((state) => state.phase);
  const awayIndex = phases.indexOf("away");
  const returningIndex = phases.indexOf("returning");
  assert.ok(awayIndex >= 0, "The idle threshold must enter the away phase");
  assert.ok(returningIndex > awayIndex, "Presence after a saved checkpoint must enter returning");
  assert.equal(phases.at(-1), "observing", "Returning must settle after its visibility window");
}

async function verifyExcludedWindowsDoNotCreateCheckpoints(): Promise<void> {
  const policy = normalizeActivityTrackingPolicy({
    idleThresholdMinutes: 1,
    excludedApplications: ["Slack"]
  });
  const captures = [
    event("2026-09-12T19:00:00.000Z", { appName: "Slack", idleSeconds: 0 }),
    event("2026-09-12T19:01:00.000Z", { appName: "Slack", idleSeconds: 60 }),
    event("2026-09-12T19:01:30.000Z", { appName: "Slack", idleSeconds: 0 })
  ];
  let currentTime = new Date(captures[0]!.timestamp);
  const states: RuntimeStatusRecord[] = [];
  let summaryCalls = 0;
  let saveCalls = 0;

  await runActivityProfile({
    captureClient: scriptedCaptures(captures, (date) => {
      currentTime = date;
    }),
    checkpointStore: {
      save: () => {
        saveCalls += 1;
      }
    },
    runtimeStore: runtimeStoreFor(policy, states),
    now: () => currentTime,
    summarize: async (events) => {
      summaryCalls += 1;
      return checkpointFor(events);
    }
  });

  assert.equal(summaryCalls, 0, "An excluded-only window must not reach the summarizer");
  assert.equal(saveCalls, 0, "An excluded-only window must not create a checkpoint");
  assert.equal(states.some((state) => state.phase === "returning"), false);
  assert.equal(states.at(-1)?.phase, "observing");
}

async function verifyStartupIdleDoesNotCreateCheckpoint(): Promise<void> {
  const policy = normalizeActivityTrackingPolicy({ idleThresholdMinutes: 1 });
  const capture = event("2026-09-12T19:30:00.000Z", {
    appName: "Finder",
    idleSeconds: 600
  });
  const states: RuntimeStatusRecord[] = [];
  let summaryCalls = 0;

  await runActivityProfile({
    captureClient: scriptedCaptures([capture], () => undefined),
    checkpointStore: { save: () => undefined },
    runtimeStore: runtimeStoreFor(policy, states),
    now: () => new Date(capture.timestamp),
    summarize: async (events) => {
      summaryCalls += 1;
      return checkpointFor(events);
    }
  });

  assert.equal(summaryCalls, 0, "Startup while already idle must not invent an away episode");
  assert.equal(states.some((state) => state.phase === "away"), false);
}

async function verifyManualCheckpointMode(): Promise<void> {
  const policy = normalizeActivityTrackingPolicy({
    checkpointTrigger: "manual",
    idleThresholdMinutes: 1
  });
  const captures = [
    event("2026-09-12T20:00:00.000Z", { appName: "Xcode", idleSeconds: 0 }),
    event("2026-09-12T20:01:00.000Z", { appName: "Xcode", idleSeconds: 60 }),
    event("2026-09-12T20:01:30.000Z", { appName: "Xcode", idleSeconds: 0 })
  ];
  let currentTime = new Date(captures[0]!.timestamp);
  const states: RuntimeStatusRecord[] = [];
  const saved: SessionCheckpoint[] = [];

  await runActivityProfile({
    captureClient: scriptedCaptures(captures, (date) => {
      currentTime = date;
    }),
    checkpointStore: {
      save: (checkpoint) => {
        saved.push(checkpoint);
      }
    },
    // The first response is checked before capture one. The second response is
    // checked after capture one and represents the native "stepping away" action.
    runtimeStore: runtimeStoreFor(policy, states, [0, 1]),
    now: () => currentTime,
    summarize: async (events) => checkpointFor(events)
  });

  assert.equal(saved.length, 1, "Manual mode must create one checkpoint for one command");
  assert.equal(states.some((state) => state.phase === "returning"), true);
}

async function openSqlite(databasePath: string): Promise<SqliteDatabase> {
  const sqlite = await import("node:sqlite") as unknown as {
    DatabaseSync: new (databasePath: string) => SqliteDatabase;
  };
  return new sqlite.DatabaseSync(databasePath);
}

async function verifySqliteRuntimeStore(): Promise<void> {
  const temporaryDirectory = await mkdtemp(path.join(tmpdir(), "continue-runtime-policy-"));
  const databasePath = path.join(temporaryDirectory, "runtime.sqlite");
  let inspector: SqliteDatabase | undefined;

  try {
    const store = createSqliteRuntimeStore(databasePath);
    assert.equal(await store.getPolicy(), null);

    const state: RuntimeStatusRecord = {
      phase: "observing",
      captureStatus: "recording",
      statusMessage: "Capturing activity",
      lastActivityAt: "2026-09-12T18:00:00.000Z",
      heartbeatAt: "2026-09-12T18:00:05.000Z"
    };
    await store.publishState(state);

    inspector = await openSqlite(databasePath);
    const stateRow = inspector.prepare(
      "SELECT phase, capture_status, status_message, last_activity_at, heartbeat_at FROM runtime_state WHERE singleton = 1"
    ).get();
    assert.deepEqual({ ...stateRow }, {
      phase: state.phase,
      capture_status: state.captureStatus,
      status_message: state.statusMessage,
      last_activity_at: state.lastActivityAt,
      heartbeat_at: state.heartbeatAt
    });

    const insertCommand = inspector.prepare(
      "INSERT INTO runtime_commands (id, command, created_at, handled_at) VALUES (?, ?, ?, ?)"
    );
    insertCommand.run("manual-away-1", "manual_away", "2026-09-12T18:00:00.000Z", null);
    insertCommand.run("manual-away-2", "manual_away", "2026-09-12T18:01:00.000Z", null);
    insertCommand.run("manual-away-handled", "manual_away", "2026-09-12T18:02:00.000Z", "2026-09-12T18:03:00.000Z");
    insertCommand.run("other-command", "refresh", "2026-09-12T18:04:00.000Z", null);

    assert.equal(await store.consumeManualAwayRequests(), 2);
    assert.equal(await store.consumeManualAwayRequests(), 0);

    const pendingManualAway = inspector.prepare(
      "SELECT COUNT(*) AS count FROM runtime_commands WHERE command = 'manual_away' AND handled_at IS NULL"
    ).get();
    assert.equal(Number(pendingManualAway?.count ?? -1), 0);
    const handledManualAway = inspector.prepare(
      "SELECT COUNT(*) AS count FROM runtime_commands WHERE command = 'manual_away' AND handled_at IS NOT NULL"
    ).get();
    assert.equal(Number(handledManualAway?.count ?? -1), 3);

    inspector.exec(`
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        ended_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        memory_json TEXT NOT NULL
      );
    `);
    const now = Date.now();
    const insertMemory = inspector.prepare(
      "INSERT INTO memories (id, ended_at, created_at, memory_json) VALUES (?, ?, ?, ?)"
    );
    const memoryRows = [
      ["older-than-retention", new Date(now - 8 * DAY_IN_MILLISECONDS).toISOString()],
      ["inside-retention", new Date(now - 2 * DAY_IN_MILLISECONDS).toISOString()],
      ["future-record", new Date(now + DAY_IN_MILLISECONDS).toISOString()]
    ] as const;
    for (const [id, endedAt] of memoryRows) {
      insertMemory.run(id, endedAt, endedAt, "{}");
    }

    await store.pruneCheckpoints(7);
    const remainingMemoryIDs = inspector.prepare(
      "SELECT id FROM memories ORDER BY id"
    ).all().map((row) => String(row.id));
    assert.deepEqual(remainingMemoryIDs, ["future-record", "inside-retention"]);
  } finally {
    inspector?.close();
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function verifySwiftWorkerRuntimeBridge(): Promise<void> {
  const temporaryDirectory = await mkdtemp(path.join(tmpdir(), "continue-runtime-bridge-"));
  const databasePath = path.join(temporaryDirectory, "memory.sqlite");
  const scratchPath = path.join(tmpdir(), "continue-runtime-bridge-swift-build");

  try {
    await run("swift", [
      "run",
      "--package-path",
      "apps/macos",
      "--scratch-path",
      scratchPath,
      "ContinueCoreChecks",
      "--write-runtime-control",
      databasePath
    ]);

    const store = createSqliteRuntimeStore(databasePath);
    assert.deepEqual(await store.getPolicy(), {
      captureEnabled: true,
      summariesEnabled: true,
      checkpointTrigger: "manual",
      idleThresholdMinutes: 11,
      observationWindowMinutes: 15,
      schedule: {
        isEnabled: true,
        startHour: 8,
        endHour: 20
      },
      excludedApplications: ["Messages"],
      checkpointRetentionDays: 30,
      screenpipeRetentionDays: 0
    });
    assert.equal(
      await store.consumeManualAwayRequests(),
      1,
      "The worker must consume the native manual-away command exactly once"
    );
    assert.equal(await store.consumeManualAwayRequests(), 0);

    const timestamp = new Date();
    await store.publishState({
      phase: "returning",
      captureStatus: "recording",
      statusMessage: "Return activity detected",
      lastActivityAt: new Date(timestamp.getTime() - 30_000).toISOString(),
      heartbeatAt: timestamp.toISOString()
    });

    await run("swift", [
      "run",
      "--package-path",
      "apps/macos",
      "--scratch-path",
      scratchPath,
      "ContinueCoreChecks",
      "--verify-runtime-state",
      databasePath
    ]);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function main(): Promise<void> {
  verifyPolicyNormalization();
  verifyScheduleAndCapture();
  verifyExclusions();
  verifyActivitySignals();
  verifyObservationAndSummaryFiltering();
  await verifySchedulerTransitionsAndRetries();
  await verifyExcludedWindowsDoNotCreateCheckpoints();
  await verifyStartupIdleDoesNotCreateCheckpoint();
  await verifyManualCheckpointMode();
  await verifySqliteRuntimeStore();
  await verifySwiftWorkerRuntimeBridge();
  console.log("Runtime policy verification passed");
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
