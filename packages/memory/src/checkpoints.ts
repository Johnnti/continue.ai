import fs from "node:fs/promises";
import path from "node:path";
import type { SessionCheckpoint, SessionMemory } from "@continue/shared";
import type { CheckpointStore, MemoryQuery } from "./types";
import { searchMemory } from "./retrieval";

async function findWorkspaceRoot(startPath: string): Promise<string> {
  let currentPath = path.resolve(startPath);

  while (true) {
    try {
      await fs.access(path.join(currentPath, "pnpm-workspace.yaml"));
      return currentPath;
    } catch {
      const parentPath = path.dirname(currentPath);
      if (parentPath === currentPath) return path.resolve(startPath);
      currentPath = parentPath;
    }
  }
}

async function readCheckpoints(storagePath: string): Promise<SessionCheckpoint[]> {
  try {
    const raw = await fs.readFile(storagePath, "utf8");
    const parsed = JSON.parse(raw) as SessionCheckpoint[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function createJsonCheckpointStore(storagePath?: string): CheckpointStore {
  const resolvedStoragePath = storagePath;
  const storagePathPromise = resolvedStoragePath
    ? Promise.resolve(resolvedStoragePath)
    : findWorkspaceRoot(process.cwd()).then((rootPath) => path.join(rootPath, "data/checkpoints.json"));

  const writeCheckpoints = async (checkpoints: SessionCheckpoint[]): Promise<void> => {
    const targetPath = await storagePathPromise;
    const temporaryPath = `${targetPath}.tmp`;
    await fs.mkdir(path.dirname(targetPath), { recursive: true });
    await fs.writeFile(temporaryPath, JSON.stringify(checkpoints, null, 2), "utf8");
    await fs.rename(temporaryPath, targetPath);
  };

  const writeMemory = async (memory: SessionMemory): Promise<void> => {
    const targetPath = await storagePathPromise;
    const current = await readCheckpoints(targetPath);
    const enriched = {
      ...memory,
      updatedAt: new Date().toISOString(),
      tags: Array.from(new Set(memory.tags ?? [])),
      facts: Array.from(new Set((memory.facts ?? []).map((fact) => `${fact.type}:${fact.value}`))).map((item) => {
        const [type, ...rest] = item.split(":");
        return { type: type as NonNullable<SessionMemory["facts"]>[number]["type"], value: rest.join(":"), label: "" };
      })
    };

    const next = [...current, enriched].slice(-100);
    await writeCheckpoints(next);
  };

  return {
    async save(checkpoint: SessionCheckpoint): Promise<void> {
      const targetPath = await storagePathPromise;
      const current = await readCheckpoints(targetPath);
      const next = [...current, checkpoint].slice(-100);
      await writeCheckpoints(next);
    },
    async getLatest(): Promise<SessionCheckpoint | null> {
      const checkpoints = await readCheckpoints(await storagePathPromise);
      return checkpoints[checkpoints.length - 1] ?? null;
    },
    async getRecent(limit: number): Promise<SessionCheckpoint[]> {
      const checkpoints = await readCheckpoints(await storagePathPromise);
      return checkpoints.slice(-Math.max(1, limit)).reverse();
    },
    async saveMemory(memory: SessionMemory): Promise<void> {
      await writeMemory(memory);
    },
    async getLatestMemory(): Promise<SessionMemory | null> {
      const checkpoints = await readCheckpoints(await storagePathPromise);
      return checkpoints[checkpoints.length - 1] ?? null;
    },
    async searchMemory(query: MemoryQuery): Promise<SessionMemory[]> {
      const memories = await readCheckpoints(await storagePathPromise);
      return searchMemory(memories, query);
    }
  };
}
