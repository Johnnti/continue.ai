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
  const timestamp = new Date().toISOString();

  if (!activity.length) {
    const checkpoint: SessionCheckpoint = {
      id: crypto.randomUUID(),
      endedAt: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
      project: "Unknown project",
      currentTask: "Recent computer activity",
      summary: "Recent activity was captured, but context confidence is low.",
      lastAction: "No clear last action detected",
      nextAction: "Review recent files or tabs to confirm where to continue",
      resumeTargets: [],
      confidence: 0.25,
      sourceWindowMinutes: 30,
      tags: ["low-confidence", "unscoped"],
      facts: [],
      context: ["No strong activity signal captured."]
    };

    return SessionCheckpointSchema.parse(checkpoint);
  }

  const last = activity[activity.length - 1];
  const confidence = estimateConfidence(activity);
  const factValues = activity
    .flatMap((event) => [event.url, event.filePath, event.windowTitle, event.appName].filter(Boolean))
    .slice(0, 6);

  const checkpoint: SessionCheckpoint = {
    ...DEMO_CHECKPOINT,
    id: crypto.randomUUID(),
    endedAt: timestamp,
    createdAt: timestamp,
    updatedAt: timestamp,
    lastAction:
      last.windowTitle ||
      last.url ||
      last.filePath ||
      "Reviewing recent activity",
    confidence,
    tags: ["session-summary", confidence > 0.7 ? "high-confidence" : "moderate-confidence"],
    facts: factValues
      .filter((value): value is string => Boolean(value))
      .slice(0, 6)
      .map((value, index) => ({
        type: value.startsWith("http") ? "url" : value.includes(".") || value.includes("/") ? "file" : "text",
        value,
        label: `Context ${index + 1}`
      })),
    context: [
      `Last observed activity: ${last.windowTitle ?? last.appName ?? "unknown"}`,
      `Captured ${activity.length} activity events in the last window.`
    ]
  };

  return SessionCheckpointSchema.parse(checkpoint);
}
