import { logger } from "@continue/shared";
import { tick } from "./scheduler";

async function main() {
  const state = await tick("away");
  logger.info("Worker tick complete", { state });
}

main().catch((error) => {
  logger.error("Worker failed", error);
  process.exitCode = 1;
});
