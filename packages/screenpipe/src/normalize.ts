import type { ActivityEvent } from "@continue/shared";

export function normalizeActivity(events: ActivityEvent[]): ActivityEvent[] {
  return events
    .filter((event) => Boolean(event.timestamp))
    .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
}
