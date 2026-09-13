import type { SessionCheckpoint } from "@continue/shared";
import type { CheckpointSearchQuery } from "./types";

const MAX_SEARCH_RESULTS = 100;

const SEARCH_STOP_WORDS = new Set([
  "a", "about", "all", "an", "and", "any", "did", "do", "doing", "for",
  "from", "i", "in", "is", "last", "me", "month", "my", "of", "on",
  "past", "recent", "recently", "show", "summary", "summaries", "tell",
  "that", "the", "this", "to", "today", "was", "week", "were", "what",
  "when", "with", "work", "worked", "yesterday", "sunday", "monday",
  "tuesday", "wednesday", "thursday", "friday", "saturday"
]);

export function normalizeSearchLimit(limit: number | undefined, fallback = 10): number {
  if (limit === undefined || !Number.isFinite(limit)) return fallback;
  return Math.min(MAX_SEARCH_RESULTS, Math.max(0, Math.floor(limit)));
}

export function memorySearchTerms(text: string | undefined): string[] {
  return Array.from(new Set(
    (text ?? "")
      .toLocaleLowerCase()
      .match(/[\p{L}\p{N}]+/gu)
      ?.filter((token) => token.length > 1 && !SEARCH_STOP_WORDS.has(token))
      ?? []
  ));
}

export function buildFtsMatchQuery(text: string | undefined): string | null {
  const terms = memorySearchTerms(text);
  if (terms.length === 0) return null;

  const prefixTerms = terms.map((term) => `"${term}"*`);
  if (terms.length === 1) return prefixTerms[0];
  return [`"${terms.join(" ")}"`, ...prefixTerms].join(" OR ");
}

export function checkpointSearchDocument(checkpoint: SessionCheckpoint) {
  const occurredAt = new Date(checkpoint.endedAt);
  const calendarDescription = Number.isNaN(occurredAt.valueOf())
    ? checkpoint.endedAt
    : occurredAt.toLocaleDateString("en-US", {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric"
      });

  return {
    occurredAt: `${checkpoint.endedAt} ${calendarDescription}`,
    project: checkpoint.project,
    currentTask: checkpoint.currentTask,
    summary: checkpoint.summary,
    lastAction: checkpoint.lastAction,
    nextAction: checkpoint.nextAction,
    keyActivities: (checkpoint.keyActivities ?? [])
      .flatMap((activity) => [
        activity.timestamp ?? "",
        activity.app,
        activity.action,
        activity.subject ?? ""
      ])
      .join(" ")
  };
}

function containsTerm(value: string, term: string): boolean {
  return value.toLocaleLowerCase().includes(term);
}

function relevanceScore(checkpoint: SessionCheckpoint, terms: string[]): number {
  const document = checkpointSearchDocument(checkpoint);
  return terms.reduce((score, term) => {
    if (containsTerm(document.project, term)) score += 8;
    if (containsTerm(document.currentTask, term)) score += 6;
    if (containsTerm(document.lastAction, term)) score += 4;
    if (containsTerm(document.nextAction, term)) score += 4;
    if (containsTerm(document.summary, term)) score += 3;
    if (containsTerm(document.keyActivities, term)) score += 2;
    if (containsTerm(document.occurredAt, term)) score += 1;
    return score;
  }, 0);
}

export function searchCheckpointList(
  checkpoints: SessionCheckpoint[],
  query: CheckpointSearchQuery = {}
): SessionCheckpoint[] {
  const limit = normalizeSearchLimit(query.limit);
  if (limit === 0) return [];
  const terms = memorySearchTerms(query.text);

  return checkpoints
    .filter((checkpoint) =>
      (!query.endedAfter || checkpoint.endedAt >= query.endedAfter)
      && (!query.endedBefore || checkpoint.endedAt < query.endedBefore))
    .map((checkpoint, index) => ({
      checkpoint,
      index,
      score: relevanceScore(checkpoint, terms)
    }))
    .filter((match) => terms.length === 0 || match.score > 0)
    .sort((left, right) =>
      right.score - left.score
      || right.checkpoint.endedAt.localeCompare(left.checkpoint.endedAt)
      || left.index - right.index)
    .slice(0, limit)
    .map((match) => match.checkpoint);
}
