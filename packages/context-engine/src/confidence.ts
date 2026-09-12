import type { ActivityEvent } from "@continue/shared";

export function estimateConfidence(activity: ActivityEvent[]): number {
  if (activity.length >= 3) return 0.86;
  if (activity.length >= 1) return 0.62;
  return 0.25;
}
