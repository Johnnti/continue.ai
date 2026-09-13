import type { SessionCheckpoint } from "@continue/shared";

export interface CheckpointSearchQuery {
  text?: string;
  /** Inclusive lower bound for the checkpoint's end time. */
  endedAfter?: string;
  /** Exclusive upper bound for the checkpoint's end time. */
  endedBefore?: string;
  limit?: number;
}

export interface CheckpointStore {
  save(checkpoint: SessionCheckpoint): Promise<void>;
  getLatest(): Promise<SessionCheckpoint | null>;
  getRecent(limit: number): Promise<SessionCheckpoint[]>;
  getById(id: string): Promise<SessionCheckpoint | null>;
  search(query: CheckpointSearchQuery): Promise<SessionCheckpoint[]>;
  close(): Promise<void>;
}
