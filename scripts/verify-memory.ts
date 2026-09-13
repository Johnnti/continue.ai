import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  createSqliteCheckpointStore,
  type CheckpointStore
} from "../packages/memory/src/index";
import type { SessionCheckpoint } from "../packages/shared/src/types";
import { searchPastSummaries } from "../packages/voice/src/agentContext";

function checkpoint(
  id: string,
  endedAt: string,
  project: string,
  summary: string
): SessionCheckpoint {
  return {
    id,
    startedAt: endedAt,
    endedAt,
    project,
    currentTask: `Work on ${project}`,
    summary,
    lastAction: `Reviewed ${project}`,
    nextAction: `Continue ${project}`,
    keyActivities: [{
      timestamp: endedAt,
      app: "Continue",
      action: "reviewed",
      subject: project,
      evidence: "observed"
    }],
    resumeTargets: [],
    confidence: 0.95,
    sourceWindowMinutes: 5,
    sourceEventCount: 10
  };
}

async function close(store: CheckpointStore) {
  await store.close();
}

async function main() {
  const directory = await mkdtemp(path.join(tmpdir(), "continue-memory-"));
  const databasePath = path.join(directory, "memory.sqlite");
  const jsonPath = path.join(directory, "checkpoints.json");

  try {
    const sqliteOnly = checkpoint(
      "sqlite-only",
      "2026-01-01T12:00:00.000Z",
      "Durable archive",
      "This row existed before the JSON migration."
    );
    const initialStore = createSqliteCheckpointStore(databasePath);
    await initialStore.save(sqliteOnly);
    await close(initialStore);

    const jsonOnly = checkpoint(
      "json-only",
      "2026-01-02T12:00:00.000Z",
      "Mercury launch page",
      "Refined the iridescent launch page and its return briefing."
    );
    await writeFile(jsonPath, JSON.stringify([jsonOnly]), "utf8");

    const store = createSqliteCheckpointStore(databasePath);
    const migrated = await store.getRecent(10);
    if (!migrated.some(({ id }) => id === sqliteOnly.id)
      || !migrated.some(({ id }) => id === jsonOnly.id)) {
      throw new Error("SQLite and JSON histories were not merged without data loss");
    }

    for (let index = 0; index < 105; index += 1) {
      await store.save(checkpoint(
        `history-${index}`,
        new Date(Date.UTC(2026, 0, 3, 0, index)).toISOString(),
        `Background project ${index}`,
        `Durable history entry ${index}`
      ));
    }

    const fullHistory = await store.getRecent(1_000);
    if (fullHistory.length !== 107) {
      throw new Error(`Expected 107 durable rows without a retention cap; found ${fullHistory.length}`);
    }

    const indexedResults = await store.search({ text: "Mercury launch", limit: 3 });
    if (indexedResults[0]?.id !== jsonOnly.id) {
      throw new Error("Full-text retrieval did not find the migrated historical checkpoint");
    }

    const directResult = await store.getById(sqliteOnly.id);
    if (directResult?.summary !== sqliteOnly.summary) {
      throw new Error("Direct checkpoint lookup did not return the durable row");
    }

    const updated = { ...jsonOnly, summary: "Updated aurora interface memory" };
    await store.save(updated);
    const updatedResults = await store.search({ text: "aurora interface", limit: 3 });
    if (updatedResults[0]?.id !== jsonOnly.id) {
      throw new Error("The search index was not updated with the checkpoint");
    }

    const voiceResults = await searchPastSummaries("aurora interface", 3, store);
    if (voiceResults.summaries[0]?.id !== jsonOnly.id) {
      throw new Error("The ElevenLabs history tool did not retrieve the SQLite result");
    }

    await close(store);
    const reopened = createSqliteCheckpointStore(databasePath);
    if ((await reopened.getById(jsonOnly.id))?.summary !== updated.summary) {
      throw new Error("The checkpoint did not survive closing and reopening SQLite");
    }
    await close(reopened);

    console.log("Memory verification passed: migration, persistence, indexed search, and voice retrieval");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
