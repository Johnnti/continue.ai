import type { SessionCheckpoint } from "@continue/shared";

export interface CheckpointStore {
  save(checkpoint: SessionCheckpoint): Promise<void>;
  getLatest(): Promise<SessionCheckpoint | null>;
  getRecent(limit: number): Promise<SessionCheckpoint[]>;
}
