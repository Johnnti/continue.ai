import { NextResponse } from "next/server";
import { getLatestCheckpoint } from "../../../lib/api";

export async function GET() {
  const checkpoint = await getLatestCheckpoint();
  return NextResponse.json({ checkpoint });
}
