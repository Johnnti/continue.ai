import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { ActivityEvent, SessionCheckpoint } from "../../../packages/shared/src/types.ts";
import { SessionCheckpointSchema } from "../../../packages/context-engine/src/schemas.ts";
import { buildReturnBriefing } from "../../../packages/voice/src/elevenlabs.ts";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const fixtureDirectory = path.resolve(
  scriptDirectory,
  "../Sources/ContinueCore/Resources/Contracts"
);

function readFixture(name: string): unknown {
  return JSON.parse(fs.readFileSync(path.join(fixtureDirectory, name), "utf8"));
}

function parseActivityEvents(value: unknown): ActivityEvent[] {
  if (!Array.isArray(value)) {
    throw new Error("Normalized activity fixture must be an array");
  }

  const allowedKeys = new Set([
    "timestamp",
    "appName",
    "windowTitle",
    "text",
    "url",
    "filePath",
    "durationSeconds"
  ]);

  return value.map((candidate, index) => {
    if (!candidate || typeof candidate !== "object") {
      throw new Error(`Activity event ${index} must be an object`);
    }

    const event = candidate as Record<string, unknown>;
    if (typeof event.timestamp !== "string" || !event.timestamp) {
      throw new Error(`Activity event ${index} must have a timestamp`);
    }

    for (const key of Object.keys(event)) {
      if (!allowedKeys.has(key)) {
        throw new Error(`Activity event ${index} has unknown field ${key}`);
      }
    }

    for (const key of ["appName", "windowTitle", "text", "url", "filePath"] as const) {
      if (event[key] !== undefined && typeof event[key] !== "string") {
        throw new Error(`Activity event ${index}.${key} must be a string`);
      }
    }

    if (
      event.durationSeconds !== undefined &&
      (typeof event.durationSeconds !== "number" || event.durationSeconds < 0)
    ) {
      throw new Error(`Activity event ${index}.durationSeconds must be non-negative`);
    }

    return event as unknown as ActivityEvent;
  });
}

const checkpoint: SessionCheckpoint = SessionCheckpointSchema
  .strict()
  .parse(readFixture("session-checkpoint-v1.json"));
const activity = parseActivityEvents(readFixture("normalized-activity-v1.json"));

for (let index = 1; index < activity.length; index += 1) {
  const previousTimestamp = Date.parse(activity[index - 1].timestamp);
  const currentTimestamp = Date.parse(activity[index].timestamp);
  if (!Number.isFinite(currentTimestamp) || currentTimestamp < previousTimestamp) {
    throw new Error("Normalized activity fixture must be chronological");
  }
}

const conversationContext = buildReturnBriefing(checkpoint);
if (
  !conversationContext.includes(checkpoint.project) ||
  !conversationContext.includes(checkpoint.nextAction)
) {
  throw new Error("Voice conversation context must retain checkpoint project and next action");
}

console.log(
  `TypeScript contracts passed: ${activity.length} activity events, ` +
    `${checkpoint.resumeTargets.length} resume targets, and one voice conversation context`
);
