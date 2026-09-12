import fs from "node:fs/promises";
import fsSync from "node:fs";
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

function findRepositoryRoot(startPath: string): string {
  let currentPath = path.resolve(startPath);
  while (currentPath !== path.dirname(currentPath)) {
    if (fsSync.existsSync(path.join(currentPath, "pnpm-workspace.yaml"))) {
      return currentPath;
    }
    currentPath = path.dirname(currentPath);
  }
  return path.resolve(startPath);
}

const defaultStoragePath = path.join(findRepositoryRoot(process.cwd()), "data/checkpoints.json");

export function createJsonCheckpointStore(storagePath = defaultStoragePath): CheckpointStore {
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
      if (limit <= 0) return [];
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints.slice(-limit).reverse();
    }
  };
}
