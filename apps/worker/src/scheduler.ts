import { logger, type ActivityEvent, type ContinueState } from "@continue/shared";
import { createScreenCaptureClient } from "@continue/screenpipe";
import { summarizeCaptureBatch } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";

export async function runActivityProfile(): Promise<void> {
  const captureClient = createScreenCaptureClient();
  const store = createCheckpointStore();
  let state: ContinueState = "observing";
  const configuredBatchSize = Number.parseInt(process.env.CONTINUE_CAPTURE_BATCH_SIZE ?? "10", 10);
  const batchSize = Number.isFinite(configuredBatchSize) && configuredBatchSize > 0 ? configuredBatchSize : 10;
  let captures: ActivityEvent[] = [];

  for await (const capture of captureClient.captures()) {
    captures.push(capture);
    if (captures.length < batchSize) continue;
    const episode = captures.slice(-batchSize);
    try {
      const checkpoint = await summarizeCaptureBatch(episode);
      await store.save(checkpoint);
      captures = [];
      state = "observing";
      logger.info("Activity profile updated", {
        state,
        startedAt: checkpoint.startedAt,
        endedAt: checkpoint.endedAt,
        observations: checkpoint.sourceEventCount
      });
    } catch (error) {
      // Keep the newest complete window so a transient provider failure can recover
      // on the next capture without terminating observation.
      captures = episode;
      logger.error("Activity episode summarization failed; retaining the batch for retry", error);
    }
  }
}
