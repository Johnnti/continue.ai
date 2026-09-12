import { NextResponse } from "next/server";
import { getRecordingStatus, startRecording } from "../../../../lib/recorder";

export async function POST() {
  const started = startRecording();
  return NextResponse.json({ started, ...getRecordingStatus() }, { status: started ? 202 : 200 });
}

export async function GET() {
  return NextResponse.json(getRecordingStatus());
}