import { DEMO_CHECKPOINT, summarizeSession } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";
import { createScreenpipeClient } from "@continue/screenpipe";
import type { SessionCheckpoint } from "@continue/shared";

const store = createCheckpointStore();
const screenpipe = createScreenpipeClient();

export async function getLatestCheckpoint() {
  const latest = await store.getLatest();
  if (latest) return latest;

  const activity = await screenpipe.getRecentActivity(30);
  const generated = activity.length ? await summarizeSession(activity) : DEMO_CHECKPOINT;
  await store.save(generated);
  return generated;
}

export async function searchMemory(query: {
  text?: string;
  project?: string;
  tags?: string[];
  limit?: number;
} = {}) {
  if (typeof store.searchMemory !== "function") {
    return [] as SessionCheckpoint[];
  }

  return store.searchMemory(query);
}
