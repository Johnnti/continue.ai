import { NextResponse } from "next/server";
import { getLatestCheckpoint } from "../../../lib/api";
import { resumeWorkspace } from "@continue/workspace";

export async function POST() {
  const checkpoint = await getLatestCheckpoint();
  if (!checkpoint) {
    return NextResponse.json({ error: "No activity profile is available yet" }, { status: 404 });
  }
  const result = await resumeWorkspace(checkpoint.resumeTargets);
  return NextResponse.json(result);
}
