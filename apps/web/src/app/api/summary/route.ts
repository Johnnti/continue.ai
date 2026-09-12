import { createCheckpointStore } from "@continue/memory";
import { NextResponse } from "next/server";
import { getCheckpointForCurrentSession } from "../../../lib/recorder";

export async function POST() {
  try {
    const checkpoint = await getCheckpointForCurrentSession()
      ?? await createCheckpointStore().getLatest();
    if (!checkpoint) throw new Error("No activity summary is available yet");
    return NextResponse.json({
      summary: checkpoint.summary,
      observations: checkpoint.sourceEventCount ?? 1,
      startedAt: checkpoint.startedAt,
      endedAt: checkpoint.endedAt,
      checkpoint
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to summarize activity";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
