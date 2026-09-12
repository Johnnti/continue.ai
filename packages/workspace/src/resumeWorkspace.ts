import type { ResumeTarget } from "@continue/shared";
import { openUrl } from "./openUrl";
import { openFile } from "./openFile";
import type { ResumeResult } from "./types";

export async function resumeWorkspace(targets: ResumeTarget[]): Promise<ResumeResult> {
  const failures: string[] = [];

  for (const target of targets) {
    try {
      if (target.type === "url") await openUrl(target.value);
      if (target.type === "file") await openFile(target.value);
      if (target.type === "app") console.log(`[workspace] open app: ${target.value}`);
    } catch (error) {
      failures.push(`${target.type}:${target.value}:${String(error)}`);
    }
  }

  return {
    attempted: targets.length,
    restored: targets.length - failures.length,
    failures,
    targets
  };
}
