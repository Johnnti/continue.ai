import { createCheckpointStore } from "@continue/memory";
import { DEMO_CHECKPOINT } from "@continue/context-engine";

export async function getLastSession() {
  const store = createCheckpointStore();
  return (await store.getLatest()) ?? DEMO_CHECKPOINT;
}

export async function getCurrentContext() {
  return getLastSession();
}
