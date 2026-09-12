import path from "node:path";
import { loadEnvFile } from "node:process";
import { logger } from "@continue/shared";
import { runActivityProfile } from "./scheduler";

try {
  loadEnvFile(path.resolve(process.cwd(), "../../.env"));
} catch {
}

runActivityProfile().catch((error) => {
  logger.error("Activity profile worker failed", error);
  process.exitCode = 1;
});
