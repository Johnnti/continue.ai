import type { ContinueState } from "@continue/shared";

export function ActivityStatus({ state }: { state: ContinueState }) {
  const label =
    state === "observing"
      ? "Observing"
      : state === "away"
        ? "Away"
        : state === "returning"
          ? "Welcome back"
          : state === "briefing"
            ? "Preparing checkpoint"
            : "Resuming";

  return <div className="card">State: {label}</div>;
}
