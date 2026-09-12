import { NextResponse } from "next/server";
import { getRecordingStatus, stopRecording } from "../../../../lib/recorder";

export async function POST() {
  const stopped = await stopRecording();
  return NextResponse.json({ stopped, ...getRecordingStatus() });
}