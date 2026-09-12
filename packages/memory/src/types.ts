import type {
  ActivityTrackingPolicy,
  RuntimeStatusRecord,
  SessionCheckpoint,
  SessionMemory
} from "@continue/shared";

export interface MemoryQuery {
  project?: string;
  tags?: string[];
  text?: string;
  limit?: number;
}

export interface CheckpointStore {
  save(checkpoint: SessionCheckpoint): Promise<void>;
  getLatest(): Promise<SessionCheckpoint | null>;
  getRecent(limit: number): Promise<SessionCheckpoint[]>;
  saveMemory?(memory: SessionMemory): Promise<void>;
  getLatestMemory?(): Promise<SessionMemory | null>;
  searchMemory?(query: MemoryQuery): Promise<SessionMemory[]>;
}

export interface RuntimeCoordinatorStore {
  getPolicy(): Promise<ActivityTrackingPolicy | null>;
  publishState(state: RuntimeStatusRecord): Promise<void>;
  consumeManualAwayRequests(): Promise<number>;
  pruneCheckpoints(retentionDays: number): Promise<void>;
}
