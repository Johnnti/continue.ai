import { NextResponse } from "next/server";
import { getRecordingStatus } from "../../../../lib/recorder";

export async function GET() {
  return NextResponse.json(getRecordingStatus());
}