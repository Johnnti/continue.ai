import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import type { SessionCheckpoint } from "@continue/shared";
import type { CheckpointStore } from "./types";
import { searchCheckpointList } from "./retrieval";

async function readCheckpoints(storagePath: string): Promise<SessionCheckpoint[]> {
  try {
    const raw = await fs.readFile(storagePath, "utf8");
    const parsed = JSON.parse(raw) as SessionCheckpoint[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
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
  async function writeCheckpoints(checkpoints: SessionCheckpoint[]) {
    await fs.mkdir(path.dirname(storagePath), { recursive: true });
    const temporaryPath = `${storagePath}.${process.pid}.tmp`;
    await fs.writeFile(temporaryPath, JSON.stringify(checkpoints, null, 2), "utf8");
    await fs.rename(temporaryPath, storagePath);
  }

  return {
    async save(checkpoint: SessionCheckpoint): Promise<void> {
      const current = await readCheckpoints(storagePath);
      const next = [...current, checkpoint].slice(-100);
      await writeCheckpoints(next);
    },
    async getLatest(): Promise<SessionCheckpoint | null> {
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints[checkpoints.length - 1] ?? null;
    },
    async getRecent(limit: number): Promise<SessionCheckpoint[]> {
      if (limit <= 0) return [];
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints.slice(-limit).reverse();
    },
    async getById(id: string): Promise<SessionCheckpoint | null> {
      const checkpoints = await readCheckpoints(storagePath);
      return checkpoints.find((checkpoint) => checkpoint.id === id) ?? null;
    },
    async search(query): Promise<SessionCheckpoint[]> {
      return searchCheckpointList(await readCheckpoints(storagePath), query);
    },
    async close(): Promise<void> {
    }
  };
}
