import { NextResponse } from "next/server";
import { createCheckpointStore } from "@continue/memory";
import { getCurrentSessionCheckpoint } from "../../../lib/recorder";

export async function GET() {
  const store = createCheckpointStore();
  const checkpoints = await store.getRecent(20);
  const current = getCurrentSessionCheckpoint();
  const checkpoint = current.hasCurrentSession
    ? current.checkpoint
    : checkpoints[0] ?? null;
  return NextResponse.json({ checkpoint, checkpoints });
}
