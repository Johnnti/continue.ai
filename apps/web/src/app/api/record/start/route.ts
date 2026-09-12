import { NextResponse } from "next/server";
import { getRecordingStatus, startRecording } from "../../../../lib/recorder";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST() {
  const started = startRecording();
  return NextResponse.json({ started, ...getRecordingStatus() }, {
    status: started ? 202 : 200,
    headers: { "Cache-Control": "no-store, max-age=0" }
  });
}

export async function GET() {
  return NextResponse.json(getRecordingStatus(), {
    headers: { "Cache-Control": "no-store, max-age=0" }
  });
}
