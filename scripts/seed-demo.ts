import { createCheckpointStore } from "@continue/memory";
import { DEMO_CHECKPOINT } from "@continue/context-engine";

async function run() {
  const store = createCheckpointStore();
  await store.save(DEMO_CHECKPOINT);
  console.log("Seeded demo checkpoint.");
}

run().catch((error) => {
  console.error("Failed to seed demo checkpoint", error);
  process.exitCode = 1;
});
