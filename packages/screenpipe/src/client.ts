import { logger } from "@continue/shared";
import type { ActivityEvent } from "@continue/shared";
import { DEMO_ACTIVITY_FIXTURE } from "./activity";
import { normalizeActivity } from "./normalize";

export interface ScreenpipeClient {
  getRecentActivity(windowMinutes?: number): Promise<ActivityEvent[]>;
  getActivitySummary(windowMinutes?: number): Promise<string>;
  getLastMeaningfulActivity(): Promise<ActivityEvent | null>;
  isScreenpipeHealthy(): Promise<boolean>;
}

export function createScreenpipeClient(baseUrl = process.env.SCREENPIPE_BASE_URL ?? "http://localhost:3030"): ScreenpipeClient {
  return {
    async getRecentActivity(): Promise<ActivityEvent[]> {
      logger.info("Using mock Screenpipe fixture", { baseUrl });
      return normalizeActivity([...DEMO_ACTIVITY_FIXTURE]);
    },
    async getActivitySummary(): Promise<string> {
      return "Mock: VS Code editing continue.ai and docs browsing for Screenpipe + ElevenLabs.";
    },
    async getLastMeaningfulActivity(): Promise<ActivityEvent | null> {
      return DEMO_ACTIVITY_FIXTURE[DEMO_ACTIVITY_FIXTURE.length - 1] ?? null;
    },
    async isScreenpipeHealthy(): Promise<boolean> {
      return true;
    }
  };
}
