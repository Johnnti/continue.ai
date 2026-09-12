import { DEMO_CHECKPOINT, summarizeSession } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";
import { createScreenpipeClient } from "@continue/screenpipe";

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
