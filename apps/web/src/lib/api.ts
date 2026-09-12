import { createCheckpointStore } from "@continue/memory";

const store = createCheckpointStore();

export async function getLatestCheckpoint() {
  return store.getLatest();
}
