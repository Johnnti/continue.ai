import fs from "node:fs/promises";
import path from "node:path";
import type { SessionCheckpoint } from "@continue/shared";
import type { CheckpointStore } from "./types";

async function readCheckpoints(storagePath: string): Promise<SessionCheckpoint[]> {
  try {
    const raw = await fs.readFile(storagePath, "utf8");
    const parsed = JSON.parse(raw) as SessionCheckpoint[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function createJsonCheckpointStore(storagePath = path.resolve(process.cwd(), "data/checkpoints.json")): CheckpointStore {
  return {
    async save(checkpoint: SessionCheckpoint): Promise<void> {
      const current = await readCheckpoints(storagePath);
      const next = [...current, checkpoint].slice(-100);
      await fs.mkdir(path.dirname(storagePath), { recursive: true });
      await fs.writeFile(storagePath, JSON.stringify(next, null, 2));
    },
    async getLatest(): Promise<SessionCheckpoint | null> {
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints[checkpoints.length - 1] ?? null;
    },
    async getRecent(limit: number): Promise<SessionCheckpoint[]> {
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints.slice(-Math.max(1, limit)).reverse();
    }
  };
}
