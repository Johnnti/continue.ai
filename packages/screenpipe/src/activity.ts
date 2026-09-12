import type { ActivityEvent } from "@continue/shared";

export const DEMO_ACTIVITY_FIXTURE: ActivityEvent[] = [
  {
    timestamp: new Date(Date.now() - 1000 * 60 * 25).toISOString(),
    appName: "Visual Studio Code",
    windowTitle: "packages/screenpipe/src/activity.ts",
    filePath: "/home/user/continue.ai/packages/screenpipe/src/activity.ts",
    durationSeconds: 420
  },
  {
    timestamp: new Date(Date.now() - 1000 * 60 * 18).toISOString(),
    appName: "Google Chrome",
    windowTitle: "Screenpipe API docs",
    url: "https://docs.screenpi.pe",
    durationSeconds: 300
  },
  {
    timestamp: new Date(Date.now() - 1000 * 60 * 10).toISOString(),
    appName: "Google Chrome",
    windowTitle: "ElevenLabs Conversational AI",
    url: "https://elevenlabs.io/docs/conversational-ai",
    durationSeconds: 240
  }
];
