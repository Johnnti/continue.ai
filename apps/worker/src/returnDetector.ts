import type { ContinueState } from "@continue/shared";

export function isReturning(previousState: ContinueState, meaningfulActivityDetected: boolean): boolean {
  return previousState === "away" && meaningfulActivityDetected;
}
