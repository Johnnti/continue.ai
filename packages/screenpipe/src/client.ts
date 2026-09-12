import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import path from "node:path";
import type { ActivityEvent } from "@continue/shared";

export interface ScreenCaptureClient {
  captures(): AsyncGenerator<ActivityEvent>;
}

export function createScreenCaptureClient(): ScreenCaptureClient {
  return {
    async *captures(): AsyncGenerator<ActivityEvent> {
      const packagePath = process.env.CONTINUE_CAPTURE_PACKAGE
        ? path.resolve(process.env.CONTINUE_CAPTURE_PACKAGE)
        : path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../apps/screen-capture-macos");
      const processHandle = spawn(
        "swift",
        ["run", "--package-path", packagePath, "continue-screen-capture"],
        { stdio: ["ignore", "pipe", "inherit"] }
      );
      const processExit = new Promise<number | null>((resolve, reject) => {
        processHandle.once("exit", resolve);
        processHandle.once("error", reject);
      });
      const lines = createInterface({ input: processHandle.stdout });

      try {
        for await (const line of lines) {
          const capture = JSON.parse(line) as ActivityEvent;
          if (!capture.timestamp || !capture.screenshotBase64) {
            throw new Error("Screen capture helper returned an incomplete capture");
          }
          yield capture;
        }
        const exitCode = await processExit;
        if (exitCode !== 0) {
          throw new Error(`Screen capture helper stopped unexpectedly (exit code ${exitCode ?? "unknown"})`);
        }
      } finally {
        lines.close();
        processHandle.kill("SIGTERM");
      }
    }
  };
}
