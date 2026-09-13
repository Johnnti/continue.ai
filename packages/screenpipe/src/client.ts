import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createInterface } from "node:readline";
import path from "node:path";
import type { ActivityEvent } from "@continue/shared";

const MAX_HELPER_ERROR_LENGTH = 8_192;

function findRepositoryRoot(startPath: string): string | null {
  let currentPath = path.resolve(startPath);
  while (currentPath !== path.dirname(currentPath)) {
    if (existsSync(path.join(currentPath, "pnpm-workspace.yaml"))) return currentPath;
    currentPath = path.dirname(currentPath);
  }
  return existsSync(path.join(currentPath, "pnpm-workspace.yaml")) ? currentPath : null;
}

function resolveCapturePackagePath(): string {
  const configuredPath = process.env.CONTINUE_CAPTURE_PACKAGE?.trim();
  if (configuredPath) return path.resolve(configuredPath);

  const repositoryRoot = findRepositoryRoot(process.cwd());
  if (!repositoryRoot) {
    throw new Error(
      "Could not locate the Continue workspace. Set CONTINUE_CAPTURE_PACKAGE to the screen-capture-macos package path."
    );
  }

  return path.join(repositoryRoot, "apps/screen-capture-macos");
}

function boundedError(output: string): string {
  const normalized = output.replace(/\s+/g, " ").trim();
  return normalized.length > MAX_HELPER_ERROR_LENGTH
    ? normalized.slice(-MAX_HELPER_ERROR_LENGTH)
    : normalized;
}

export interface ScreenCaptureClient {
  captures(): AsyncGenerator<ActivityEvent>;
  stop(): void;
}

export function createScreenCaptureClient(): ScreenCaptureClient {
  let activeProcess: ReturnType<typeof spawn> | null = null;
  return {
    stop() {
      activeProcess?.kill("SIGTERM");
    },
    async *captures(): AsyncGenerator<ActivityEvent> {
      const packagePath = resolveCapturePackagePath();
      if (!existsSync(path.join(packagePath, "Package.swift"))) {
        throw new Error(`Screen capture package was not found at ${packagePath}`);
      }

      const processHandle = spawn(
        "swift",
        ["run", "--package-path", packagePath, "continue-screen-capture"],
        { stdio: ["ignore", "pipe", "pipe"] }
      );
      activeProcess = processHandle;
      let stderr = "";
      processHandle.stderr?.setEncoding("utf8");
      processHandle.stderr?.on("data", (chunk: string | Buffer) => {
        stderr = `${stderr}${chunk}`.slice(-MAX_HELPER_ERROR_LENGTH);
      });

      const processExit = new Promise<number | null>((resolve, reject) => {
        processHandle.once("close", resolve);
        processHandle.once("error", reject);
      });
      if (!processHandle.stdout) {
        processHandle.kill("SIGTERM");
        throw new Error("Screen capture helper did not expose an output stream");
      }
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
          const diagnostic = boundedError(stderr);
          throw new Error(
            `Screen capture helper stopped unexpectedly (exit code ${exitCode ?? "unknown"})${
              diagnostic ? `: ${diagnostic}` : ""
            }`
          );
        }
      } finally {
        lines.close();
        processHandle.kill("SIGTERM");
        if (activeProcess === processHandle) activeProcess = null;
      }
    }
  };
}
