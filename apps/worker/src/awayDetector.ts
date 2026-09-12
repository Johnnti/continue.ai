import { DEFAULT_AWAY_THRESHOLD_MINUTES } from "@continue/shared";

export function getAwayThresholdMinutes(): number {
  const configured = Number(process.env.CONTINUE_AWAY_THRESHOLD_MINUTES);
  if (!Number.isFinite(configured) || configured <= 0) {
    return DEFAULT_AWAY_THRESHOLD_MINUTES;
  }
  return configured;
}

export function isAway(minutesSinceMeaningfulActivity: number): boolean {
  return minutesSinceMeaningfulActivity >= getAwayThresholdMinutes();
}
