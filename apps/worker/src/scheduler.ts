import type { ContinueState } from "@continue/shared";
import { createScreenpipeClient } from "@continue/screenpipe";
import { summarizeSession } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";
import { sendCheckpointToElevenLabs } from "@continue/voice";
import { isAway } from "./awayDetector";
import { isReturning } from "./returnDetector";

export async function tick(previousState: ContinueState = "observing"): Promise<ContinueState> {
  const screenpipe = createScreenpipeClient();
  const store = createCheckpointStore();
  const activity = await screenpipe.getRecentActivity(30);
  const last = await screenpipe.getLastMeaningfulActivity();
  const minutesSince = last
    ? (Date.now() - new Date(last.timestamp).getTime()) / (1000 * 60)
    : Number.POSITIVE_INFINITY;

  if (isAway(minutesSince)) {
    const checkpoint = await summarizeSession(activity);
    await store.save(checkpoint);
    return "away";
  }

  if (isReturning(previousState, activity.length > 0)) {
    const latest = await store.getLatest();
    if (latest) {
      await sendCheckpointToElevenLabs(latest);
    }
    return "returning";
  }

  return "observing";
}
