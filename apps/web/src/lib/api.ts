import { createCheckpointStore } from "@continue/memory";
import type { SessionCheckpoint } from "@continue/shared";

const store = createCheckpointStore();

export async function getLatestCheckpoint() {
  return store.getLatest();
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
