import type { ActivityEvent, KeyActivity, ResumeTarget, SessionCheckpoint } from "@continue/shared";
import { logger } from "@continue/shared";
import path from "node:path";
import { loadEnvFile } from "node:process";
import { SessionCheckpointSchema } from "./schemas";
import { CONTEXT_ENGINE_PROMPT } from "./prompts";

function getLlmConfig() {
  try {
    loadEnvFile(path.resolve(process.cwd(), "../../.env"));
  } catch {
  }
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey || apiKey === "your-api-key" || apiKey === "replace-with-your-api-key") {
    throw new Error("Set OPENAI_API_KEY to a real provider key in .env before starting the activity worker.");
  }
  return {
    apiKey,
    model: process.env.OPENAI_MODEL ?? "gpt-4o-mini",
    baseUrl: (process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1").replace(/\/$/, "")
  };
}

function describeCapture(capture: ActivityEvent, index: number): string {
  const context = [
    `Observation ${index + 1} at ${capture.timestamp}`,
    capture.displayId !== undefined ? `captured display: ${capture.displayId}` : undefined,
    capture.appName ? `foreground app: ${capture.appName}` : undefined,
    capture.windowTitle ? `window: ${capture.windowTitle}` : undefined,
    capture.url ? `visible URL: ${capture.url}` : undefined,
    capture.filePath ? `visible file: ${capture.filePath}` : undefined,
    capture.focusedElementRole ? `focused control role: ${capture.focusedElementRole}` : undefined,
    capture.focusedElementLabel ? `focused control label: ${capture.focusedElementLabel}` : undefined
  ].filter(Boolean).join("; ");
  const interactions = capture.interactions?.map((interaction) => {
    const target = [interaction.elementRole, interaction.elementLabel].filter(Boolean).join(": ");
    const location = interaction.x !== undefined && interaction.y !== undefined
      ? ` at (${Math.round(interaction.x)}, ${Math.round(interaction.y)})`
      : "";
    const app = interaction.appName ? ` in ${interaction.appName}` : "";
    const window = interaction.windowTitle ? ` — ${interaction.windowTitle}` : "";
    return `${interaction.timestamp}: ${interaction.type}${location}${app}${window}${target ? ` on ${target}` : ""}`;
  }).join("\n") ?? "";
  return interactions ? `${context}\nNative activity since the previous observation:\n${interactions}` : context;
}

async function requestBatchSummary(captures: ActivityEvent[]): Promise<string> {
  const config = getLlmConfig();
  const configuredDetail = process.env.CONTINUE_VISION_DETAIL;
  const imageDetail = configuredDetail === "low" || configuredDetail === "high" ? configuredDetail : "auto";
  const response = await fetch(`${config.baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: config.model,
      temperature: 0.1,
      messages: [{
        role: "user",
        content: [
          { type: "text", text: `${CONTEXT_ENGINE_PROMPT}\n\nThe observations below are chronological, oldest first.` },
          ...captures.flatMap((capture, index) => [
            { type: "text" as const, text: describeCapture(capture, index) },
            {
              type: "image_url" as const,
              image_url: {
                url: `data:${capture.screenshotMimeType ?? "image/png"};base64,${capture.screenshotBase64}`,
                detail: imageDetail
              }
            }
          ])
        ]
      }]
    })
  });

  if (!response.ok) {
    throw new Error(`LLM request failed (${response.status}): ${await response.text()}`);
  }
  const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  const output = payload.choices?.[0]?.message?.content?.trim();
  if (!output) throw new Error("LLM returned an empty activity summary");
  logger.info("LLM activity episode summarized", { observations: captures.length });
  return output;
}

function parseSummary(raw: string): Omit<SessionCheckpoint, "id" | "endedAt" | "sourceWindowMinutes"> {
  const json = raw.replace(/^```json\s*/, "").replace(/\s*```$/, "");
  const parsed = JSON.parse(json) as {
    project: string;
    currentTask: string;
    summary: string;
    lastAction: string;
    nextAction: string;
    keyActivities: KeyActivity[];
    resumeTargets: ResumeTarget[];
    confidence: number;
  };
  return parsed;
}

export async function summarizeCaptureBatch(captures: ActivityEvent[]): Promise<SessionCheckpoint> {
  if (!captures.length || captures.some((capture) => !capture.screenshotBase64)) {
    throw new Error("Cannot summarize an activity episode without screenshot data");
  }
  const ordered = [...captures].sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp));
  const summary = parseSummary(await requestBatchSummary(ordered));
  const startedAt = ordered[0].timestamp;
  const endedAt = ordered[ordered.length - 1].timestamp;
  const elapsedMinutes = Math.max(1, Math.ceil((Date.parse(endedAt) - Date.parse(startedAt)) / 60_000));
  return SessionCheckpointSchema.parse({
    ...summary,
    id: crypto.randomUUID(),
    startedAt,
    endedAt,
    sourceWindowMinutes: elapsedMinutes,
    sourceEventCount: ordered.length
  });
}

export async function summarizeCapture(capture: ActivityEvent): Promise<SessionCheckpoint> {
  return summarizeCaptureBatch([capture]);
}
