import { NextResponse } from "next/server";
import { getRecordingStatus } from "../../../../lib/recorder";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  return NextResponse.json(getRecordingStatus(), {
    headers: { "Cache-Control": "no-store, max-age=0" }
  });
}
