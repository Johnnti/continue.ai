import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import path from "node:path";
import type { ActivityEvent } from "@continue/shared";

export interface ScreenCaptureClient {
  captures(): AsyncGenerator<ActivityEvent>;
  /** Interrupt an in-flight capture request and release the helper process. */
  stop(): void;
}

export function createScreenCaptureClient(): ScreenCaptureClient {
  let processHandle: ReturnType<typeof spawn> | null = null;
  let stopRequested = false;

  return {
    stop() {
      stopRequested = true;
      if (processHandle && processHandle.exitCode === null && !processHandle.killed) {
        processHandle.kill("SIGTERM");
      }
    },

    async *captures(): AsyncGenerator<ActivityEvent> {
      const packagePath = process.env.CONTINUE_CAPTURE_PACKAGE
        ? path.resolve(process.env.CONTINUE_CAPTURE_PACKAGE)
        : path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../apps/screen-capture-macos");
      const helperProcess = spawn(
        "swift",
        ["run", "--package-path", packagePath, "continue-screen-capture"],
        { stdio: ["ignore", "pipe", "pipe"] }
      );
      processHandle = helperProcess;
      if (stopRequested) {
        helperProcess.kill("SIGTERM");
      }
      let errorOutput = "";
      helperProcess.stderr?.setEncoding("utf8");
      helperProcess.stderr?.on("data", (chunk: string) => {
        errorOutput = `${errorOutput}${chunk}`.slice(-4_096);
      });
      const processExit = new Promise<number | null>((resolve, reject) => {
        helperProcess.once("exit", resolve);
        helperProcess.once("error", reject);
      });
      const lines = createInterface({ input: helperProcess.stdout });

      try {
        for await (const line of lines) {
          const capture = JSON.parse(line) as ActivityEvent;
          if (!capture.timestamp || !capture.screenshotBase64) {
            throw new Error("Screen capture helper returned an incomplete capture");
          }
          yield capture;
        }
        const exitCode = await processExit;
        if (exitCode !== 0 && !stopRequested) {
          const detail = errorOutput.trim();
          throw new Error(
            detail || `Screen capture helper stopped unexpectedly (exit code ${exitCode ?? "unknown"})`
          );
        }
      } finally {
        lines.close();
        if (helperProcess.exitCode === null && !helperProcess.killed) {
          helperProcess.kill("SIGTERM");
        }
        if (processHandle === helperProcess) {
          processHandle = null;
        }
      }
    }
  };
}
