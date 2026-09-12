import { createScreenCaptureClient, type ScreenCaptureClient } from "@continue/screenpipe";
import { summarizeCaptureBatch } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";
import { logger, type ActivityEvent, type SessionCheckpoint } from "@continue/shared";

interface RecorderState {
  iterator: AsyncGenerator<ActivityEvent> | null;
  client: ScreenCaptureClient | null;
  processingPromise: Promise<void> | null;
  recording: boolean;
  capturesProcessed: number;
  lastError: string | null;
  sessionStartedAt: string | null;
  pendingCaptures: ActivityEvent[];
  currentCheckpoint: SessionCheckpoint | null;
  summaryPromise: Promise<SessionCheckpoint> | null;
  latestCapture: {
    timestamp: string;
    appName?: string;
    windowTitle?: string;
    displayName?: string;
    displayId?: number;
  } | null;
}

const recorderGlobal = globalThis as typeof globalThis & { __continueRecorder?: RecorderState };
const state = recorderGlobal.__continueRecorder ?? {
  iterator: null,
  client: null,
  processingPromise: null,
  recording: false,
  capturesProcessed: 0,
  lastError: null,
  sessionStartedAt: null,
  pendingCaptures: [],
  currentCheckpoint: null,
  summaryPromise: null,
  latestCapture: null
};
recorderGlobal.__continueRecorder = state;

// Preserve state across Next.js development reloads while adding newly introduced fields.
state.client ??= null;
state.processingPromise ??= null;
state.sessionStartedAt ??= null;
state.pendingCaptures ??= [];
state.currentCheckpoint ??= null;
state.summaryPromise ??= null;
state.latestCapture ??= null;

export function getRecordingStatus() {
  return {
    recording: state.recording,
    capturesProcessed: state.capturesProcessed,
    pendingCaptures: state.pendingCaptures.length,
    sessionStartedAt: state.sessionStartedAt,
    latestSummaryAt: state.currentCheckpoint?.endedAt ?? null,
    latestCapture: state.latestCapture,
    lastError: state.lastError ?? null
  };
}

export function startRecording(): boolean {
  if (state.recording || state.processingPromise) return false;
  state.recording = true;
  state.capturesProcessed = 0;
  state.lastError = null;
  state.sessionStartedAt = new Date().toISOString();
  state.pendingCaptures = [];
  state.currentCheckpoint = null;
  state.summaryPromise = null;
  state.latestCapture = null;
  const captureClient = createScreenCaptureClient();
  const captureIterator = captureClient.captures();
  state.client = captureClient;
  state.iterator = captureIterator;
  const processingPromise = processCaptures(captureIterator);
  state.processingPromise = processingPromise;
  void processingPromise
    .catch((error) => {
      state.lastError = error instanceof Error ? error.message : "The screen capture helper failed";
      logger.error("Screen recording failed", error);
    })
    .finally(() => {
      if (state.processingPromise === processingPromise) state.processingPromise = null;
    });
  return true;
}

export async function stopRecording(): Promise<boolean> {
  const wasRecording = state.recording;
  if (!wasRecording && !state.processingPromise) return false;
  state.recording = false;
  state.client?.stop();
  try {
    await state.iterator?.return(undefined);
  } catch (error) {
    state.lastError = error instanceof Error ? error.message : "The screen capture helper could not stop cleanly";
    logger.error("Screen recording stop failed", error);
  }
  try {
    await state.processingPromise;
  } catch {
    // The background handler records the helper error in status. Stopping a
    // failed session should still return a normal status payload to the app.
  }
  state.client = null;
  state.iterator = null;
  return wasRecording;
}

async function processCaptures(captureIterator: AsyncGenerator<ActivityEvent>) {
  const configuredBatchSize = Number.parseInt(process.env.CONTINUE_CAPTURE_BATCH_SIZE ?? "10", 10);
  const batchSize = Number.isFinite(configuredBatchSize) && configuredBatchSize > 0 ? configuredBatchSize : 10;
  try {
    for await (const capture of captureIterator) {
      if (!state.recording) break;
      state.capturesProcessed += 1;
      state.latestCapture = {
        timestamp: capture.timestamp,
        appName: capture.appName,
        windowTitle: capture.windowTitle,
        displayName: capture.displayName,
        displayId: capture.displayId
      };
      state.pendingCaptures.push(capture);
      if (state.pendingCaptures.length < batchSize) continue;
      const episode = state.pendingCaptures.slice(0, batchSize);
      try {
        await persistEpisode(episode);
      } catch (error) {
        state.lastError = error instanceof Error
          ? error.message
          : "Activity episode summarization failed";
        logger.error("Activity episode summarization failed; retaining the batch for retry", error);
      }
    }
  } finally {
    if (state.pendingCaptures.length) {
      try {
        await persistEpisode([...state.pendingCaptures]);
      } catch (error) {
        state.lastError = error instanceof Error
          ? error.message
          : "Unable to summarize the final activity episode";
        logger.error("Unable to summarize the final partial activity episode", error);
      }
    }
    state.recording = false;
    state.client = null;
    state.iterator = null;
  }
}

async function persistEpisode(episode: ActivityEvent[]): Promise<SessionCheckpoint> {
  if (state.summaryPromise) return state.summaryPromise;

  const promise = (async () => {
    const checkpoint = await summarizeCaptureBatch(episode);
    await createCheckpointStore().save(checkpoint);
    const capturedEvents = new Set(episode);
    state.pendingCaptures = state.pendingCaptures.filter((capture) => !capturedEvents.has(capture));
    state.currentCheckpoint = checkpoint;
    state.lastError = null;
    return checkpoint;
  })();
  state.summaryPromise = promise;
  try {
    return await promise;
  } finally {
    if (state.summaryPromise === promise) state.summaryPromise = null;
  }
}

export async function getCheckpointForCurrentSession(): Promise<SessionCheckpoint | null> {
  if (state.summaryPromise) return state.summaryPromise;
  if (state.pendingCaptures.length) return persistEpisode([...state.pendingCaptures]);
  if (state.currentCheckpoint) return state.currentCheckpoint;
  if (state.lastError) throw new Error(state.lastError);
  if (state.sessionStartedAt) {
    throw new Error("The current recording has not captured a frame yet. Wait a moment and try again.");
  }
  return null;
}
