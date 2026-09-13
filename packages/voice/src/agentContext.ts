import { createCheckpointStore } from "@continue/memory";
import { toVoiceCheckpoint } from "./elevenlabs";
import type { VoiceBootstrapContext, VoiceHistoryResult } from "./types";

const DEFAULT_HISTORY_LIMIT = 20;
const MAX_HISTORY_RESULTS = 10;

type CheckpointReader = ReturnType<typeof createCheckpointStore>;

function normalizedLimit(limit: number | undefined, fallback: number, maximum: number) {
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(maximum, Math.max(1, Math.floor(limit ?? fallback)));
}

function startOfLocalDay(value: Date) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function addLocalDays(value: Date, count: number) {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate() + count);
}

function temporalRange(query: string): { endedAfter?: string; endedBefore?: string } {
  const normalized = query.toLocaleLowerCase();
  const now = new Date();
  const today = startOfLocalDay(now);
  const isoRange = (start: Date, end: Date) => ({
    endedAfter: start.toISOString(),
    endedBefore: end.toISOString()
  });

  if (normalized.includes("yesterday")) {
    return isoRange(addLocalDays(today, -1), today);
  }

  if (normalized.includes("today")) {
    return isoRange(today, addLocalDays(today, 1));
  }

  if (normalized.includes("last week")) {
    const daysSinceMonday = (now.getDay() + 6) % 7;
    const thisMonday = addLocalDays(today, -daysSinceMonday);
    const previousMonday = addLocalDays(thisMonday, -7);
    return isoRange(previousMonday, thisMonday);
  }

  if (normalized.includes("last month")) {
    const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const previousMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    return isoRange(previousMonth, thisMonth);
  }

  const weekdays = [
    "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"
  ];
  const weekday = weekdays.findIndex((name) => normalized.includes(name));
  if (weekday >= 0) {
    const daysAgo = (now.getDay() - weekday + 7) % 7;
    const start = addLocalDays(today, -daysAgo);
    return isoRange(start, addLocalDays(start, 1));
  }

  const isoDate = normalized.match(/\b(\d{4})-(\d{2})-(\d{2})\b/);
  if (isoDate) {
    const start = new Date(`${isoDate[1]}-${isoDate[2]}-${isoDate[3]}T00:00:00`);
    if (!Number.isNaN(start.valueOf())) {
      return isoRange(start, addLocalDays(start, 1));
    }
  }

  return {};
}

export async function getLastSession(store: CheckpointReader = createCheckpointStore()) {
  return store.getLatest();
}

export async function getCurrentContext(store: CheckpointReader = createCheckpointStore()) {
  return getLastSession(store);
}

export async function getCheckpointContext(
  checkpointId: string | undefined,
  store: CheckpointReader = createCheckpointStore()
) {
  if (!checkpointId) return getLastSession(store);
  return store.getById(checkpointId);
}

export async function getVoiceBootstrapContext(
  limit = DEFAULT_HISTORY_LIMIT,
  store: CheckpointReader = createCheckpointStore()
): Promise<VoiceBootstrapContext> {
  const checkpoints = await store.getRecent(
    normalizedLimit(limit, DEFAULT_HISTORY_LIMIT, DEFAULT_HISTORY_LIMIT)
  );
  return {
    current: checkpoints[0] ? toVoiceCheckpoint(checkpoints[0]) : null,
    recent: checkpoints.map(toVoiceCheckpoint)
  };
}

export async function searchPastSummaries(
  query: string,
  limit = 3,
  store: CheckpointReader = createCheckpointStore()
): Promise<VoiceHistoryResult> {
  const normalizedQuery = query.trim();
  const resultLimit = normalizedLimit(limit, 3, MAX_HISTORY_RESULTS);
  const matches = await store.search({
    text: normalizedQuery,
    ...temporalRange(normalizedQuery),
    limit: resultLimit
  });

  return {
    query: normalizedQuery,
    summaries: matches.map(toVoiceCheckpoint)
  };
}
