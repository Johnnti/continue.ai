import { NextResponse } from "next/server";

const DEFAULT_VOICE_ID = "JBFqnCBsd6RMkjVDRZzb";
const MAX_SPEECH_CHARACTERS = 10_000;

export const dynamic = "force-dynamic";

interface SpeechRequest {
  text?: unknown;
}

function errorMessage(payload: unknown, fallback: string) {
  if (!payload || typeof payload !== "object") return fallback;
  const detail = (payload as { detail?: unknown }).detail;
  if (typeof detail === "string") return detail;
  if (detail && typeof detail === "object") {
    const message = (detail as { message?: unknown }).message;
    if (typeof message === "string") return message;
  }
  return fallback;
}

export async function POST(request: Request) {
  const apiKey = process.env.ELEVENLABS_API_KEY?.trim();
  if (!apiKey) {
    return NextResponse.json(
      { error: "ELEVENLABS_API_KEY is not configured" },
      { status: 503 },
    );
  }

  let payload: SpeechRequest;
  try {
    payload = (await request.json()) as SpeechRequest;
  } catch {
    return NextResponse.json({ error: "A JSON request body is required" }, { status: 400 });
  }

  const text = typeof payload.text === "string" ? payload.text.trim() : "";
  if (!text) {
    return NextResponse.json({ error: "No activity summary was supplied" }, { status: 400 });
  }
  if (text.length > MAX_SPEECH_CHARACTERS) {
    return NextResponse.json(
      { error: `Activity summary exceeds ${MAX_SPEECH_CHARACTERS} characters` },
      { status: 400 },
    );
  }

  const voiceId =
    process.env.CONTINUE_ELEVENLABS_VOICE_ID?.trim() ||
    process.env.ELEVENLABS_VOICE_ID?.trim() ||
    DEFAULT_VOICE_ID;
  const url = new URL(
    `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceId)}`,
  );
  url.searchParams.set("output_format", "mp3_44100_128");

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "xi-api-key": apiKey,
      },
      body: JSON.stringify({
        text,
        model_id: "eleven_flash_v2_5",
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      const details = await response.json().catch(() => null);
      const fallback = `ElevenLabs speech generation failed with HTTP ${response.status}`;
      return NextResponse.json(
        { error: errorMessage(details, fallback) },
        { status: response.status >= 500 ? 502 : response.status },
      );
    }

    return new NextResponse(await response.arrayBuffer(), {
      status: 200,
      headers: {
        "Content-Type": "audio/mpeg",
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unable to reach ElevenLabs";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
