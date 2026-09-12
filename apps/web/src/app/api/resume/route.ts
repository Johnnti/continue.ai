import { NextResponse } from "next/server";
import { getLatestCheckpoint } from "../../../lib/api";
import { resumeWorkspace } from "@continue/workspace";

export async function POST() {
  const checkpoint = await getLatestCheckpoint();
  const result = await resumeWorkspace(checkpoint.resumeTargets);
  return NextResponse.json(result);
}
