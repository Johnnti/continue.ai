import { createCheckpointStore } from "@continue/memory";
import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type ChatRole = "user" | "assistant";

interface ChatMessage {
  role: ChatRole;
  content: string;
}

interface ChatRequest {
  messages?: unknown;
}

function normalizeMessages(value: unknown): ChatMessage[] {
  if (!Array.isArray(value)) return [];
  return value
    .slice(-20)
    .flatMap((item): ChatMessage[] => {
      if (!item || typeof item !== "object") return [];
      const role = (item as { role?: unknown }).role;
      const content = (item as { content?: unknown }).content;
      if ((role !== "user" && role !== "assistant") || typeof content !== "string") {
        return [];
      }
      const normalized = content.trim().slice(0, 4_000);
      return normalized ? [{ role, content: normalized }] : [];
    });
}

function outputText(payload: unknown): string {
  if (!payload || typeof payload !== "object") return "";
  const direct = (payload as { output_text?: unknown }).output_text;
  if (typeof direct === "string") return direct.trim();
  const output = (payload as { output?: unknown }).output;
  if (!Array.isArray(output)) return "";
  return output
    .flatMap((item) => {
      if (!item || typeof item !== "object") return [];
      const content = (item as { content?: unknown }).content;
      if (!Array.isArray(content)) return [];
      return content.flatMap((part) => {
        if (!part || typeof part !== "object") return [];
        const text = (part as { text?: unknown }).text;
        return typeof text === "string" ? [text] : [];
      });
    })
    .join("\n")
    .trim();
}

export async function POST(request: Request) {
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    return NextResponse.json({ error: "OPENAI_API_KEY is not configured" }, { status: 503 });
  }

  let body: ChatRequest;
  try {
    body = (await request.json()) as ChatRequest;
  } catch {
    return NextResponse.json({ error: "A JSON request body is required" }, { status: 400 });
  }

  const messages = normalizeMessages(body.messages);
  if (!messages.length || messages.at(-1)?.role !== "user") {
    return NextResponse.json({ error: "The conversation must end with a user message" }, { status: 400 });
  }

  const checkpoint = await createCheckpointStore().getLatest();
  const activityContext = checkpoint
    ? [
        `Project: ${checkpoint.project}`,
        `Task: ${checkpoint.currentTask}`,
        `Activity summary: ${checkpoint.summary}`,
        `Last action: ${checkpoint.lastAction}`,
        `Suggested next action: ${checkpoint.nextAction}`,
      ].join("\n")
    : "No completed activity checkpoint is currently available.";

  try {
    const response = await fetch(
      `${(process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1").replace(/\/$/, "")}/responses`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: process.env.OPENAI_CHAT_MODEL ?? process.env.OPENAI_MODEL ?? "gpt-4o-mini",
          store: false,
          instructions:
            "You are Continue, a concise context-resume assistant. Answer questions using the supplied activity checkpoint and conversation. Be honest when the checkpoint does not establish something. Help the user remember what they did and decide what to do next. Never invent private message contents that were intentionally omitted.",
          input: [
            { role: "developer", content: `Latest activity checkpoint:\n${activityContext}` },
            ...messages,
          ],
          max_output_tokens: 500,
        }),
        cache: "no-store",
      },
    );
    const payload = (await response.json()) as unknown;
    if (!response.ok) {
      const message =
        payload && typeof payload === "object"
          ? (payload as { error?: { message?: string } }).error?.message
          : undefined;
      throw new Error(message ?? `OpenAI returned HTTP ${response.status}`);
    }
    const reply = outputText(payload);
    if (!reply) throw new Error("OpenAI returned an empty response");
    return NextResponse.json({ reply });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to generate a reply";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
