import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createSqliteCheckpointStore } from "../packages/memory/src/sqlite";
import type { SessionCheckpoint } from "../packages/shared/src/types";

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

async function main(): Promise<void> {
  const temporaryDirectory = await mkdtemp(path.join(tmpdir(), "continue-sqlite-bridge-"));
  const databasePath = path.join(temporaryDirectory, "memory.sqlite");
  const checkpointID = `typescript-${randomUUID()}`;
  const checkpoint: SessionCheckpoint = {
    id: checkpointID,
    startedAt: "2026-09-12T17:55:00Z",
    endedAt: "2026-09-12T18:00:00Z",
    project: "continue.ai",
    currentTask: "Verifying the shared SQLite bridge",
    summary: "The TypeScript memory package wrote this checkpoint for the Swift integration check.",
    lastAction: "Persisted a canonical checkpoint through createSqliteCheckpointStore",
    nextAction: "Read the same row through SQLiteCheckpointProvider",
    resumeTargets: [
      {
        type: "url",
        value: "https://example.com/continue",
        label: "Continue integration reference"
      }
    ],
    confidence: 0.95,
    sourceWindowMinutes: 5,
    sourceEventCount: 10,
    createdAt: "2026-09-12T18:00:00Z"
  };

  try {
    const store = createSqliteCheckpointStore(databasePath);
    await store.save(checkpoint);

    const latest = await store.getLatest();
    if (latest?.id !== checkpointID) {
      throw new Error("The TypeScript memory store did not return the checkpoint it wrote");
    }

    const emptyHistory = await store.getRecent(0);
    if (emptyHistory.length !== 0) {
      throw new Error("A zero TypeScript history limit must return no checkpoints");
    }

    await run("swift", [
      "run",
      "--package-path",
      "apps/macos",
      "ContinueCoreChecks",
      "--verify-external-database",
      databasePath,
      checkpointID
    ]);

    console.log("SQLite bridge verification passed: TypeScript write -> Swift read");
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
