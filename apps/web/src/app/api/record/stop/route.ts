import { NextResponse } from "next/server";
import { getRecordingStatus, stopRecording } from "../../../../lib/recorder";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST() {
  const stopped = await stopRecording();
  return NextResponse.json({ stopped, ...getRecordingStatus() }, {
    headers: { "Cache-Control": "no-store, max-age=0" }
  });
}
