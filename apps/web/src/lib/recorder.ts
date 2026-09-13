import { createScreenCaptureClient, type ScreenCaptureClient } from "@continue/screenpipe";
import { summarizeCaptureBatch } from "@continue/context-engine";
import { createCheckpointStore } from "@continue/memory";
import { logger, type ActivityEvent, type SessionCheckpoint } from "@continue/shared";

interface RecorderState {
  iterator: AsyncGenerator<ActivityEvent> | null;
  captureClient: ScreenCaptureClient | null;
  processingTask: Promise<void> | null;
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
  captureClient: null,
  processingTask: null,
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
state.sessionStartedAt ??= null;
state.pendingCaptures ??= [];
state.currentCheckpoint ??= null;
state.summaryPromise ??= null;
state.latestCapture ??= null;
state.processingTask ??= null;
state.captureClient ??= null;

export function getRecordingStatus() {
  return {
    recording: state.recording,
    processing: state.processingTask !== null,
    capturesProcessed: state.capturesProcessed,
    pendingCaptures: state.pendingCaptures.length,
    sessionStartedAt: state.sessionStartedAt,
    latestSummaryAt: state.currentCheckpoint?.endedAt ?? null,
    latestCapture: state.latestCapture,
    lastError: state.lastError ?? null
  };
}

export function getCurrentSessionCheckpoint() {
  return {
    hasCurrentSession: state.sessionStartedAt !== null,
    checkpoint: state.currentCheckpoint
  };
}

export function startRecording(): boolean {
  if (state.recording || state.processingTask) return false;
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
  state.iterator = captureIterator;
  state.captureClient = captureClient;
  const processingTask = processCaptures(captureIterator);
  state.processingTask = processingTask;
  void processingTask
    .catch((error) => {
      state.lastError ??= error instanceof Error ? error.message : "The screen capture helper failed";
      logger.error("Screen recording failed", error);
    })
    .finally(() => {
      if (state.processingTask === processingTask) state.processingTask = null;
    });
  return true;
}

export async function stopRecording(): Promise<boolean> {
  if (!state.recording) return false;
  state.recording = false;
  const iterator = state.iterator;
  const processingTask = state.processingTask;
  state.captureClient?.stop();
  await iterator?.return(undefined);
  await processingTask?.catch(() => undefined);
  if (state.processingTask === processingTask) state.processingTask = null;
  state.iterator = null;
  state.captureClient = null;
  return true;
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
        logger.error("Activity episode summarization failed; retaining the batch for retry", error);
      }
    }
  } finally {
    if (state.pendingCaptures.length) {
      try {
        await persistEpisode([...state.pendingCaptures]);
      } catch (error) {
        state.lastError ??= error instanceof Error
          ? error.message
          : "Unable to summarize the final partial activity episode";
        logger.error("Unable to summarize the final partial activity episode", error);
      }
    }
    state.recording = false;
    state.iterator = null;
    state.captureClient = null;
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
