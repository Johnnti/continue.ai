import { createCheckpointStore } from "@continue/memory";

export async function getLastSession() {
  const store = createCheckpointStore();
  return store.getLatest();
}

export async function getCurrentContext() {
  return getLastSession();
}
