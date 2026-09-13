import { NextRequest, NextResponse } from "next/server";
import {
  getCheckpointContext,
  getVoiceBootstrapContext,
  searchPastSummaries,
  toVoiceCheckpoint
} from "@continue/voice";

export const dynamic = "force-dynamic";

function noStoreJson(value: unknown, status = 200) {
  return NextResponse.json(value, {
    status,
    headers: { "Cache-Control": "no-store" }
  });
}

export async function GET(request: NextRequest) {
  const mode = request.nextUrl.searchParams.get("mode") ?? "bootstrap";

  try {
    if (mode === "search") {
      const query = request.nextUrl.searchParams.get("query") ?? "";
      const requestedLimit = Number.parseInt(
        request.nextUrl.searchParams.get("limit") ?? "3",
        10
      );
      return noStoreJson(await searchPastSummaries(query, requestedLimit));
    }

    if (mode === "checkpoint") {
      const checkpoint = await getCheckpointContext(
        request.nextUrl.searchParams.get("id") ?? undefined
      );
      return noStoreJson({
        checkpoint: checkpoint ? toVoiceCheckpoint(checkpoint) : null
      });
    }

    if (mode !== "bootstrap") {
      return noStoreJson({ error: `Unknown voice context mode: ${mode}` }, 400);
    }

    return noStoreJson(await getVoiceBootstrapContext());
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Unable to load voice context";
    return noStoreJson({ error: message }, 500);
  }
}
