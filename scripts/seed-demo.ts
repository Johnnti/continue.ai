import { createSqliteCheckpointStore } from "../packages/memory/src/sqlite";
import type { SessionCheckpoint } from "../packages/shared/src/types";

async function main(): Promise<void> {
  const endedAt = new Date();
  const startedAt = new Date(endedAt.getTime() - 30 * 60 * 1_000);
  const checkpoint: SessionCheckpoint = {
    id: "continue-local-demo",
    startedAt: startedAt.toISOString(),
    endedAt: endedAt.toISOString(),
    project: "continue.ai",
    currentTask: "Preparing the Continue desktop integration",
    summary: "You were reviewing the native desktop interface, shared checkpoint database, and voice integration.",
    lastAction: "Verified that the TypeScript memory store and Swift desktop app share the same SQLite record",
    nextAction: "Open the desktop preview and review the seeded checkpoint",
    resumeTargets: [
      {
        type: "file",
        value: "README.md",
        label: "Run and architecture guide"
      },
      {
        type: "file",
        value: "docs/PRODUCT_DECISIONS.md",
        label: "Product decisions"
      }
    ],
    confidence: 0.96,
    sourceWindowMinutes: 30,
    sourceEventCount: 12,
    createdAt: endedAt.toISOString()
  };

  const store = createSqliteCheckpointStore();
  await store.save(checkpoint);
  console.log("Seeded data/memory.sqlite with checkpoint continue-local-demo.");
}

main().catch((error: unknown) => {
  console.error("Failed to seed the demo checkpoint", error);
  process.exitCode = 1;
});
