import {
  DEFAULT_ACTIVITY_TRACKING_POLICY,
  type ActivityEvent,
  type ActivityTrackingPolicy,
  type TrackingSchedulePolicy
} from "@continue/shared";

type PolicyInput = Partial<ActivityTrackingPolicy> & {
  schedule?: Partial<TrackingSchedulePolicy>;
};

const OBSERVATION_WINDOW_OPTIONS = [5, 15, 30, 60] as const;
const CHECKPOINT_RETENTION_OPTIONS = [1, 7, 30] as const;
const SCREENPIPE_RETENTION_OPTIONS = [0, 1, 7, 30] as const;

/**
 * Keep policy handling at the worker boundary. Settings are persisted by the
 * runtime store, so a malformed or partially migrated record must not make the
 * capture loop throw or accidentally enable a broader capture window.
 */
export function normalizeActivityTrackingPolicy(input?: PolicyInput | null): ActivityTrackingPolicy {
  const policy = input ?? {};
  const schedule: Partial<TrackingSchedulePolicy> = policy.schedule ?? {};
  const checkpointTrigger = policy.checkpointTrigger;
  const validTrigger = checkpointTrigger === "automatic"
    || checkpointTrigger === "manual"
    || checkpointTrigger === "automaticAndManual";

  return {
    captureEnabled: typeof policy.captureEnabled === "boolean"
      ? policy.captureEnabled
      : DEFAULT_ACTIVITY_TRACKING_POLICY.captureEnabled,
    summariesEnabled: typeof policy.summariesEnabled === "boolean"
      ? policy.summariesEnabled
      : DEFAULT_ACTIVITY_TRACKING_POLICY.summariesEnabled,
    checkpointTrigger: validTrigger ? checkpointTrigger : DEFAULT_ACTIVITY_TRACKING_POLICY.checkpointTrigger,
    idleThresholdMinutes: clampedInteger(
      policy.idleThresholdMinutes,
      DEFAULT_ACTIVITY_TRACKING_POLICY.idleThresholdMinutes,
      1,
      60
    ),
    observationWindowMinutes: nearestOption(
      policy.observationWindowMinutes,
      OBSERVATION_WINDOW_OPTIONS,
      DEFAULT_ACTIVITY_TRACKING_POLICY.observationWindowMinutes
    ),
    checkpointRetentionDays: allowedInteger(
      policy.checkpointRetentionDays,
      CHECKPOINT_RETENTION_OPTIONS,
      DEFAULT_ACTIVITY_TRACKING_POLICY.checkpointRetentionDays
    ),
    screenpipeRetentionDays: allowedInteger(
      policy.screenpipeRetentionDays,
      SCREENPIPE_RETENTION_OPTIONS,
      DEFAULT_ACTIVITY_TRACKING_POLICY.screenpipeRetentionDays
    ),
    excludedApplications: normalizeExcludedApplications(policy.excludedApplications),
    schedule: {
      isEnabled: typeof schedule.isEnabled === "boolean"
        ? schedule.isEnabled
        : DEFAULT_ACTIVITY_TRACKING_POLICY.schedule.isEnabled,
      startHour: normalizedHour(schedule.startHour ?? DEFAULT_ACTIVITY_TRACKING_POLICY.schedule.startHour),
      endHour: normalizedHour(schedule.endHour ?? DEFAULT_ACTIVITY_TRACKING_POLICY.schedule.endHour)
    }
  };
}

function clampedInteger(value: number | undefined, fallback: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.trunc(Number(value))));
}

function nearestOption(value: number | undefined, options: readonly number[], fallback: number): number {
  if (!Number.isFinite(value)) return fallback;
  return options.reduce((nearest, option) => (
    Math.abs(option - Number(value)) < Math.abs(nearest - Number(value)) ? option : nearest
  ), options[0] ?? fallback);
}

function allowedInteger(value: number | undefined, options: readonly number[], fallback: number): number {
  return Number.isInteger(value) && options.includes(Number(value)) ? Number(value) : fallback;
}

function normalizedHour(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(23, Math.max(0, Math.trunc(value)));
}

export function normalizeExcludedApplications(applications?: string[] | null): string[] {
  if (!Array.isArray(applications)) return [];
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const application of applications) {
    if (typeof application !== "string") continue;
    const value = application.trim();
    if (!value) continue;
    const key = value.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    normalized.push(value);
  }
  return normalized;
}

export function isApplicationExcluded(application: string | undefined, excludedApplications: string[]): boolean {
  if (!application) return false;
  const key = application.trim().toLocaleLowerCase();
  if (!key) return false;
  return excludedApplications.some((excluded) => excluded.trim().toLocaleLowerCase() === key);
}

/** Return whether a local wall-clock time is inside the configured daily window. */
export function isWithinTrackingSchedule(
  policy: Pick<ActivityTrackingPolicy, "schedule">,
  at: Date = new Date()
): boolean {
  const schedule = policy.schedule;
  if (!schedule.isEnabled) return true;

  const hour = at.getHours();
  const startHour = normalizedHour(schedule.startHour);
  const endHour = normalizedHour(schedule.endHour);

  // Equal bounds represent an all-day schedule, matching the native settings
  // model and avoiding an accidental zero-minute capture window.
  if (startHour === endHour) return true;
  if (startHour < endHour) return hour >= startHour && hour < endHour;
  return hour >= startHour || hour < endHour;
}

export function isCaptureActive(policy: ActivityTrackingPolicy, at: Date = new Date()): boolean {
  return policy.captureEnabled && isWithinTrackingSchedule(policy, at);
}

export function allowsAutomaticCheckpoint(policy: Pick<ActivityTrackingPolicy, "checkpointTrigger">): boolean {
  return policy.checkpointTrigger === "automatic" || policy.checkpointTrigger === "automaticAndManual";
}

export function allowsManualCheckpoint(policy: Pick<ActivityTrackingPolicy, "checkpointTrigger">): boolean {
  return policy.checkpointTrigger === "manual" || policy.checkpointTrigger === "automaticAndManual";
}

function parsedTime(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function comparableContext(event: ActivityEvent): Array<string | number | undefined> {
  return [
    event.appName,
    event.windowTitle,
    event.url,
    event.filePath,
    event.text,
    event.focusedElementRole,
    event.focusedElementLabel
  ];
}

/**
 * Screenpipe's interaction stream and app/window changes are the fallback
 * presence signal when the native capture does not expose idleSeconds.
 */
export function hasContextChange(previous: ActivityEvent | undefined, current: ActivityEvent): boolean {
  if (!previous) return true;
  const previousContext = comparableContext(previous);
  const currentContext = comparableContext(current);
  return previousContext.some((value, index) => value !== currentContext[index]);
}

export function hasFallbackPresence(previous: ActivityEvent | undefined, current: ActivityEvent): boolean {
  return Boolean(current.interactions?.length) || hasContextChange(previous, current);
}

export interface ActivitySignal {
  /** True when this capture proves recent user presence. */
  presenceDetected: boolean;
  /** Capture-provided or fallback-estimated idle duration in seconds. */
  idleSeconds: number;
  /** Timestamp of the latest known meaningful input, when available. */
  lastActivityAt: string | null;
  /** True when idleSeconds came from the capture helper. */
  usedCaptureIdle: boolean;
}

function activityTimestamp(
  event: ActivityEvent,
  idleSeconds: number | null,
  fallbackNow: Date
): string {
  const eventTime = parsedTime(event.timestamp);
  if (eventTime === null) return fallbackNow.toISOString();
  if (idleSeconds === null || idleSeconds <= 0) return new Date(eventTime).toISOString();
  return new Date(eventTime - idleSeconds * 1000).toISOString();
}

/**
 * Resolve presence from one capture. A valid capture idle value takes
 * precedence over inferred app/window changes; fallback inference only runs
 * when the helper omitted idleSeconds.
 */
export function getActivitySignal(
  current: ActivityEvent,
  previous: ActivityEvent | undefined,
  lastActivityAt: string | null,
  idleThresholdMinutes: number,
  fallbackNow: Date = new Date()
): ActivitySignal {
  const thresholdSeconds = clampedInteger(idleThresholdMinutes, 1, 1, 60) * 60;
  const captureIdle = typeof current.idleSeconds === "number"
    && Number.isFinite(current.idleSeconds)
    && current.idleSeconds >= 0
    ? current.idleSeconds
    : null;

  if (captureIdle !== null) {
    return {
      presenceDetected: captureIdle < thresholdSeconds,
      idleSeconds: captureIdle,
      lastActivityAt: activityTimestamp(current, captureIdle, fallbackNow),
      usedCaptureIdle: true
    };
  }

  const fallbackPresence = hasFallbackPresence(previous, current);
  const currentTime = parsedTime(current.timestamp) ?? fallbackNow.getTime();
  const previousActivityTime = parsedTime(lastActivityAt ?? undefined);
  const elapsedSeconds = previousActivityTime === null
    ? (fallbackPresence ? 0 : thresholdSeconds)
    : Math.max(0, (currentTime - previousActivityTime) / 1000);

  return {
    presenceDetected: fallbackPresence,
    idleSeconds: fallbackPresence ? 0 : elapsedSeconds,
    lastActivityAt: fallbackPresence ? activityTimestamp(current, null, fallbackNow) : lastActivityAt,
    usedCaptureIdle: false
  };
}

/** Keep the newest timestamp-bounded window while preserving arrival order. */
export function trimObservationsToWindow(events: ActivityEvent[], windowMinutes: number): ActivityEvent[] {
  if (events.length === 0) return [];
  const boundedWindowMinutes = clampedInteger(windowMinutes, 1, 1, 60);
  const windowMs = boundedWindowMinutes * 60_000;
  // The native helper's minimum interval is one second. This count limit keeps
  // memory bounded even if an upstream adapter repeats a timestamp.
  const maximumObservationCount = boundedWindowMinutes * 60;
  const timestamps = events
    .map((event) => parsedTime(event.timestamp))
    .filter((timestamp): timestamp is number => timestamp !== null);
  if (timestamps.length === 0) return events.slice(-1);

  const newest = Math.max(...timestamps);
  const cutoff = newest - windowMs;
  return events.filter((event) => {
    const timestamp = parsedTime(event.timestamp);
    return timestamp !== null && timestamp >= cutoff;
  }).slice(-maximumObservationCount);
}

function sanitizeInteractions(event: ActivityEvent, excludedApplications: string[]): ActivityEvent {
  if (!event.interactions) return event;
  const interactions = event.interactions.filter(
    (interaction) => !isApplicationExcluded(interaction.appName, excludedApplications)
  );
  if (interactions.length === event.interactions.length) return event;
  return { ...event, interactions };
}

/**
 * Remove excluded foreground applications from model input. Input from an
 * excluded app still reaches the presence detector before this filter runs.
 */
export function filterSummaryObservations(
  events: ActivityEvent[],
  excludedApplications: string[]
): ActivityEvent[] {
  if (excludedApplications.length === 0) return [...events];

  return events
    .filter((event) => {
      if (isApplicationExcluded(event.appName, excludedApplications)) return false;
      if (event.appName) return true;
      const interactions = event.interactions ?? [];
      return interactions.length === 0 || interactions.some(
        (interaction) => !isApplicationExcluded(interaction.appName, excludedApplications)
      );
    })
    .map((event) => sanitizeInteractions(event, excludedApplications));
}
