import type { ActivityEvent, SessionCheckpoint } from "@continue/shared";
import { SessionCheckpointSchema } from "./schemas";
import { estimateConfidence } from "./confidence";

export const DEMO_CHECKPOINT: SessionCheckpoint = {
  id: "demo-checkpoint",
  endedAt: new Date().toISOString(),
  project: "continue.ai",
  currentTask: "Integrating Screenpipe with the context engine",
  summary: "You were wiring Screenpipe activity into checkpoint generation for continue.ai.",
  lastAction: "Reviewing the Screenpipe API and editing the activity integration",
  nextAction: "Connect the generated checkpoint to the ElevenLabs voice agent",
  resumeTargets: [
    { type: "url", value: "https://docs.screenpi.pe", label: "Screenpipe docs" },
    { type: "url", value: "https://elevenlabs.io/docs/conversational-ai", label: "ElevenLabs docs" },
    { type: "file", value: "packages/screenpipe/src/client.ts", label: "Screenpipe client" }
  ],
  confidence: 0.86,
  sourceWindowMinutes: 30
};

export async function summarizeSession(activity: ActivityEvent[]): Promise<SessionCheckpoint> {
  if (!activity.length) {
    return {
      id: crypto.randomUUID(),
      endedAt: new Date().toISOString(),
      project: "Unknown project",
      currentTask: "Recent computer activity",
      summary: "Recent activity was captured, but context confidence is low.",
      lastAction: "No clear last action detected",
      nextAction: "Review recent files or tabs to confirm where to continue",
      resumeTargets: [],
      confidence: 0.25,
      sourceWindowMinutes: 30
    };
  }

  const last = activity[activity.length - 1];
  const checkpoint: SessionCheckpoint = {
    ...DEMO_CHECKPOINT,
    id: crypto.randomUUID(),
    endedAt: new Date().toISOString(),
    lastAction:
      last.windowTitle ||
      last.url ||
      last.filePath ||
      "Reviewing recent activity",
    confidence: estimateConfidence(activity)
  };

  return SessionCheckpointSchema.parse(checkpoint);
}
