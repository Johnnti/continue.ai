import {
  logger,
  type ActivityEvent,
  type ActivityTrackingPolicy,
  type RuntimePhase,
  type RuntimeStatusRecord,
  type SessionCheckpoint
} from "@continue/shared";
import { createScreenCaptureClient } from "@continue/screenpipe";
import { summarizeCaptureBatch } from "@continue/context-engine";
import { createCheckpointStore, createSqliteRuntimeStore } from "@continue/memory";
import {
  allowsAutomaticCheckpoint,
  allowsManualCheckpoint,
  filterSummaryObservations,
  getActivitySignal,
  isCaptureActive,
  normalizeActivityTrackingPolicy,
  trimObservationsToWindow
} from "./activityPolicy";

const RETURNING_VISIBILITY_MS = 60_000;
const DEFAULT_POLICY_POLL_MS = 30_000;
const DEFAULT_CAPTURE_RETRY_MS = 5_000;

interface CaptureClientLike {
  captures(): AsyncIterable<ActivityEvent>;
}

interface CheckpointStoreLike {
  save(checkpoint: SessionCheckpoint): Promise<void> | void;
}

type CheckpointSummarizer = (events: ActivityEvent[]) => Promise<SessionCheckpoint>;

/**
 * Runtime persistence is intentionally kept small. The concrete SQLite
 * implementation can evolve without making the scheduler depend on its SQL
 * details, and tests can provide an in-memory implementation of this shape.
 */
export interface RuntimeStoreLike {
  getPolicy(): Promise<ActivityTrackingPolicy | null> | ActivityTrackingPolicy | null;
  publishState(record: RuntimeStatusRecord): Promise<void> | void;
  consumeManualAwayRequests(): Promise<number> | number;
  pruneCheckpoints(retentionDays: number): Promise<void> | void;
}

export interface ActivitySchedulerOptions {
  captureClient?: CaptureClientLike;
  checkpointStore?: CheckpointStoreLike;
  runtimeStore?: RuntimeStoreLike;
  summarize?: CheckpointSummarizer;
  now?: () => Date;
  sleep?: (milliseconds: number) => Promise<void>;
  signal?: AbortSignal;
  policyPollIntervalMs?: number;
  captureRetryDelayMs?: number;
  returningVisibilityMs?: number;
}

type CheckpointOutcome = "notStarted" | "pending" | "saved" | "skipped";

interface EpisodeState {
  phase: RuntimePhase;
  observations: ActivityEvent[];
  previousCapture?: ActivityEvent;
  hasObservedPresence: boolean;
  lastActivityAt: string | null;
  pendingSummary: ActivityEvent[] | null;
  checkpointOutcome: CheckpointOutcome;
  returningUntil: number | null;
}

interface SchedulerContext {
  checkpointStore: CheckpointStoreLike;
  runtimeStore: RuntimeStoreLike;
  summarize: CheckpointSummarizer;
  now: () => Date;
  returningVisibilityMs: number;
}

function newEpisode(lastActivityAt: string | null = null): EpisodeState {
  return {
    phase: "observing",
    observations: [],
    hasObservedPresence: false,
    lastActivityAt,
    pendingSummary: null,
    checkpointOutcome: "notStarted",
    returningUntil: null
  };
}

function configuredInterval(names: string[], fallback: number): number {
  for (const name of names) {
    const value = Number(process.env[name]);
    if (Number.isFinite(value) && value >= 0) return value;
  }
  return fallback;
}

function validNow(now: () => Date): Date {
  const value = now();
  return value instanceof Date && Number.isFinite(value.getTime()) ? value : new Date();
}

function latestActivityTimestamp(
  current: string | null,
  candidate: string | null
): string | null {
  if (!candidate) return current;
  if (!current) return candidate;

  const currentTime = Date.parse(current);
  const candidateTime = Date.parse(candidate);
  if (!Number.isFinite(currentTime) || !Number.isFinite(candidateTime)) return current;
  return candidateTime > currentTime ? candidate : current;
}

function isStopped(signal: AbortSignal | undefined): boolean {
  return Boolean(signal?.aborted);
}

function defaultSleep(milliseconds: number, signal?: AbortSignal): Promise<void> {
  if (milliseconds <= 0 || signal?.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const finish = () => {
      if (timer !== undefined) clearTimeout(timer);
      signal?.removeEventListener("abort", finish);
      resolve();
    };
    timer = setTimeout(finish, milliseconds);
    signal?.addEventListener("abort", finish, { once: true });
  });
}

function statusMessage(
  phase: RuntimePhase,
  captureStatus: RuntimeStatusRecord["captureStatus"],
  summariesEnabled: boolean,
  detail?: string
): string {
  if (captureStatus === "paused") return "Activity capture paused";
  if (captureStatus === "unavailable") return detail ?? "Screen capture unavailable; retrying";
  if (!summariesEnabled) return "Screenpipe recording; Continue summaries paused";
  if (detail) return detail;
  switch (phase) {
    case "away":
      return "Away mode is active";
    case "returning":
      return "Return activity detected";
    default:
      return "Observing activity";
  }
}

async function publishState(
  runtimeStore: RuntimeStoreLike,
  now: () => Date,
  phase: RuntimePhase,
  captureStatus: RuntimeStatusRecord["captureStatus"],
  summariesEnabled: boolean,
  lastActivityAt: string | null,
  detail?: string
): Promise<void> {
  const heartbeatAt = validNow(now).toISOString();
  const record: RuntimeStatusRecord = {
    phase,
    captureStatus,
    statusMessage: statusMessage(phase, captureStatus, summariesEnabled, detail),
    lastActivityAt,
    heartbeatAt
  };
  try {
    await runtimeStore.publishState(record);
  } catch (error) {
    // A status write must not terminate capture or lose a pending checkpoint.
    logger.error("Unable to publish activity runtime state", error);
  }
}

async function closeCaptureIterator(iterator: AsyncIterator<ActivityEvent> | undefined): Promise<void> {
  if (!iterator?.return) return;
  try {
    await iterator.return();
  } catch (error) {
    logger.warn("Screen capture helper did not close cleanly", error);
  }
}

async function readPolicy(runtimeStore: RuntimeStoreLike): Promise<ActivityTrackingPolicy> {
  return normalizeActivityTrackingPolicy(await runtimeStore.getPolicy());
}

async function consumeManualAwayRequest(runtimeStore: RuntimeStoreLike): Promise<boolean> {
  try {
    return await runtimeStore.consumeManualAwayRequests() > 0;
  } catch (error) {
    logger.error("Unable to consume manual away requests", error);
    return false;
  }
}

async function pruneCheckpoints(runtimeStore: RuntimeStoreLike, retentionDays: number): Promise<void> {
  try {
    await runtimeStore.pruneCheckpoints(retentionDays);
  } catch (error) {
    // Retention is maintenance. A failed prune must not make the just-created
    // checkpoint look like a failed summarization.
    logger.error("Unable to prune expired checkpoints", error);
  }
}

function observationWindow(
  observations: ActivityEvent[],
  policy: ActivityTrackingPolicy
): ActivityEvent[] {
  return trimObservationsToWindow(observations, policy.observationWindowMinutes);
}

function resetEpisodeForPause(previous: EpisodeState): EpisodeState {
  // Keep the last known activity for the paused status card, but discard raw
  // observations and away markers before capture resumes.
  return newEpisode(previous.lastActivityAt);
}

function resetEpisodeForSummaryPause(previous: EpisodeState): EpisodeState {
  return newEpisode(previous.lastActivityAt);
}

export async function runActivityProfile(options: ActivitySchedulerOptions = {}): Promise<void> {
  const captureClient: CaptureClientLike = options.captureClient ?? createScreenCaptureClient();
  const checkpointStore: CheckpointStoreLike = options.checkpointStore ?? createCheckpointStore();
  const runtimeStore: RuntimeStoreLike = options.runtimeStore
    ?? createSqliteRuntimeStore();
  const now = options.now ?? (() => new Date());
  const context: SchedulerContext = {
    checkpointStore,
    runtimeStore,
    summarize: options.summarize ?? summarizeCaptureBatch,
    now,
    returningVisibilityMs: options.returningVisibilityMs ?? RETURNING_VISIBILITY_MS
  };
  const signal = options.signal;
  const sleep = options.sleep ?? ((milliseconds: number) => defaultSleep(milliseconds, signal));
  const policyPollIntervalMs = options.policyPollIntervalMs
    ?? configuredInterval(["CONTINUE_POLICY_POLL_INTERVAL_MS", "CONTINUE_POLICY_POLL_MS"], DEFAULT_POLICY_POLL_MS);
  const captureRetryDelayMs = options.captureRetryDelayMs
    ?? configuredInterval(["CONTINUE_CAPTURE_RETRY_INTERVAL_MS", "CONTINUE_CAPTURE_RETRY_MS"], DEFAULT_CAPTURE_RETRY_MS);

  let episode = newEpisode();
  let iterator: AsyncIterator<ActivityEvent> | undefined;
  let lastPrunedRetentionDays: number | null = null;

  try {
    while (!isStopped(signal)) {
      let policy: ActivityTrackingPolicy;
      try {
        policy = await readPolicy(runtimeStore);
      } catch (error) {
        logger.error("Unable to read activity tracking policy", error);
        await publishState(
          runtimeStore,
          now,
          episode.phase,
          "unavailable",
          true,
          episode.lastActivityAt,
          "Activity policy unavailable; retrying"
        );
        await sleep(captureRetryDelayMs);
        continue;
      }

      if (lastPrunedRetentionDays !== policy.checkpointRetentionDays) {
        await pruneCheckpoints(runtimeStore, policy.checkpointRetentionDays);
        lastPrunedRetentionDays = policy.checkpointRetentionDays;
      }

      const captureActive = isCaptureActive(policy, validNow(now));
      if (!captureActive) {
        await closeCaptureIterator(iterator);
        iterator = undefined;
        episode = resetEpisodeForPause(episode);

        // Consume commands even while paused so a stale menu-bar request cannot
        // unexpectedly create a checkpoint on a later schedule window.
        await consumeManualAwayRequest(runtimeStore);
        await publishState(
          runtimeStore,
          now,
          "observing",
          "paused",
          policy.summariesEnabled,
          episode.lastActivityAt
        );
        await sleep(policyPollIntervalMs);
        continue;
      }

      if (!policy.summariesEnabled && episode.phase !== "observing") {
        episode = resetEpisodeForSummaryPause(episode);
      }

      if (!iterator) {
        try {
          iterator = captureClient.captures()[Symbol.asyncIterator]();
          await publishState(
            runtimeStore,
            now,
            episode.phase,
            "recording",
            policy.summariesEnabled,
            episode.lastActivityAt
          );
        } catch (error) {
          logger.error("Unable to start the screen capture helper", error);
          await publishState(
            runtimeStore,
            now,
            episode.phase,
            "unavailable",
            policy.summariesEnabled,
            episode.lastActivityAt
          );
          await sleep(captureRetryDelayMs);
          continue;
        }
      }

      // A manual request can arrive between capture events. Process it before
      // waiting for the next frame, then process again after that frame.
      const manualBeforeCapture = await consumeManualAwayRequest(runtimeStore);
      if (manualBeforeCapture && policy.summariesEnabled && allowsManualCheckpoint(policy) && episode.phase === "observing") {
        await enterAway(episode, policy, context);
      }

      let nextCapture: IteratorResult<ActivityEvent>;
      try {
        nextCapture = await iterator.next();
      } catch (error) {
        logger.error("Screen capture helper failed; retrying", error);
        await closeCaptureIterator(iterator);
        iterator = undefined;
        await publishState(
          runtimeStore,
          now,
          episode.phase,
          "unavailable",
          policy.summariesEnabled,
          episode.lastActivityAt
        );
        await sleep(captureRetryDelayMs);
        continue;
      }

      // A graceful generator completion is treated as worker shutdown. The
      // concrete Screenpipe adapter throws for an unexpected helper exit, so a
      // thrown result enters the retry path above without making test streams
      // loop forever.
      if (nextCapture.done) {
        iterator = undefined;
        return;
      }

      const capture = nextCapture.value;
      await processCapture(capture, episode, policy, context);

      const manualAfterCapture = await consumeManualAwayRequest(runtimeStore);
      if (manualAfterCapture && policy.summariesEnabled && allowsManualCheckpoint(policy) && episode.phase === "observing") {
        await enterAway(episode, policy, context);
      }

      await publishState(
        runtimeStore,
        now,
        episode.phase,
        "recording",
        policy.summariesEnabled,
        episode.lastActivityAt
      );
    }
  } finally {
    await closeCaptureIterator(iterator);
  }
}

async function processCapture(
  capture: ActivityEvent,
  episode: EpisodeState,
  policy: ActivityTrackingPolicy,
  context: SchedulerContext
): Promise<void> {
  const signal = getActivitySignal(
    capture,
    episode.previousCapture,
    episode.lastActivityAt,
    policy.idleThresholdMinutes,
    validNow(context.now)
  );
  episode.previousCapture = capture;
  if (signal.presenceDetected) {
    episode.hasObservedPresence = true;
  }
  if (signal.presenceDetected || signal.usedCaptureIdle) {
    episode.lastActivityAt = latestActivityTimestamp(
      episode.lastActivityAt,
      signal.lastActivityAt
    );
  }

  if (!policy.summariesEnabled) {
    // Capture remains recording while interpretation is paused. Keep only the
    // small presence baseline needed to classify a future event.
    if (episode.phase !== "observing") {
      episode.phase = "observing";
      episode.pendingSummary = null;
      episode.checkpointOutcome = "notStarted";
      episode.returningUntil = null;
    }
    return;
  }

  if (
    episode.phase === "returning"
    && episode.returningUntil !== null
    && validNow(context.now).getTime() >= episode.returningUntil
  ) {
    episode.phase = "observing";
    episode.returningUntil = null;
    episode.pendingSummary = null;
    episode.checkpointOutcome = "notStarted";
    episode.observations = [];
  }

  episode.observations = observationWindow([...episode.observations, capture], policy);

  if (episode.phase === "away") {
    // A failed summary remains associated with this away transition and is
    // retried on the next complete capture window, never duplicated.
    await attemptCheckpoint(episode, policy, context);
    if (signal.presenceDetected && episode.checkpointOutcome === "saved") {
      await enterReturning(episode, context);
    } else if (signal.presenceDetected && episode.checkpointOutcome === "skipped") {
      resetSkippedEpisode(episode, capture);
    }
  } else if (
    episode.phase === "observing"
    && episode.hasObservedPresence
    && allowsAutomaticCheckpoint(policy)
    && !signal.presenceDetected
    && signal.idleSeconds >= policy.idleThresholdMinutes * 60
  ) {
    await enterAway(episode, policy, context);
  }
}

async function enterAway(
  episode: EpisodeState,
  policy: ActivityTrackingPolicy,
  context: SchedulerContext
): Promise<void> {
  if (episode.phase !== "observing") return;

  episode.phase = "away";
  episode.returningUntil = null;
  episode.checkpointOutcome = "pending";
  episode.pendingSummary = filterSummaryObservations(
    observationWindow(episode.observations, policy),
    policy.excludedApplications
  );

  await publishState(
    context.runtimeStore,
    context.now,
    "away",
    "recording",
    policy.summariesEnabled,
    episode.lastActivityAt,
    "Away detected; preparing checkpoint"
  );
  await attemptCheckpoint(episode, policy, context);
}

async function attemptCheckpoint(
  episode: EpisodeState,
  policy: ActivityTrackingPolicy,
  context: SchedulerContext
): Promise<void> {
  if (episode.checkpointOutcome !== "pending" || !episode.pendingSummary || !policy.summariesEnabled) return;
  if (episode.pendingSummary.length === 0) {
    // An all-excluded observation window is intentionally not sent to the
    // model. Mark this away transition handled so later frames cannot create a
    // checkpoint containing excluded application data.
    episode.checkpointOutcome = "skipped";
    episode.pendingSummary = null;
    logger.info("Skipped checkpoint because the away window only contained excluded applications");
    return;
  }

  const pending = episode.pendingSummary;
  try {
    const checkpoint = await context.summarize(pending);
    await context.checkpointStore.save(checkpoint);
    // Set this before pruning. The checkpoint is durable even if maintenance
    // fails, and retrying the model would create a duplicate checkpoint.
    episode.checkpointOutcome = "saved";
    episode.pendingSummary = null;
    await pruneCheckpoints(context.runtimeStore, policy.checkpointRetentionDays);
    logger.info("Activity checkpoint saved", {
      state: episode.phase,
      startedAt: checkpoint.startedAt,
      endedAt: checkpoint.endedAt,
      observations: checkpoint.sourceEventCount
    });
    await publishState(
      context.runtimeStore,
      context.now,
      episode.phase,
      "recording",
      policy.summariesEnabled,
      episode.lastActivityAt,
      "Away checkpoint saved"
    );
  } catch (error) {
    // Keep the exact window so a transient provider or database failure can
    // recover without dropping evidence or making another away checkpoint.
    episode.pendingSummary = pending;
    logger.error("Activity checkpoint failed; retaining the window for retry", error);
  }
}

async function enterReturning(
  episode: EpisodeState,
  context: SchedulerContext
): Promise<void> {
  if (episode.phase !== "away") return;
  episode.phase = "returning";
  episode.returningUntil = validNow(context.now).getTime() + context.returningVisibilityMs;
  await publishState(
    context.runtimeStore,
    context.now,
    "returning",
    "recording",
    true,
    episode.lastActivityAt,
    "Return activity detected"
  );
}

function resetSkippedEpisode(episode: EpisodeState, capture: ActivityEvent): void {
  episode.phase = "observing";
  episode.observations = [capture];
  episode.hasObservedPresence = true;
  episode.pendingSummary = null;
  episode.checkpointOutcome = "notStarted";
  episode.returningUntil = null;
}

export const RETURNING_STATE_MINIMUM_MS = RETURNING_VISIBILITY_MS;
