import { NextResponse } from "next/server";
import { searchMemory } from "../../../lib/api";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const results = await searchMemory({
    text: searchParams.get("text") ?? undefined,
    project: searchParams.get("project") ?? undefined,
    tags: searchParams.get("tags") ? searchParams.get("tags")!.split(",") : undefined,
    limit: Number(searchParams.get("limit") ?? "10")
  });

  return NextResponse.json({ results });
}
