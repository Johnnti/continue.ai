import type { SessionCheckpoint } from "@continue/shared";

export interface VoiceBriefingContext {
  checkpoint: SessionCheckpoint;
}

/**
 * The deliberately small checkpoint shape exposed to a voice conversation.
 * Resume targets stay local because a spoken or typed query only needs the
 * interpreted summary, not paths or URLs that could be treated as actions.
 */
export interface VoiceCheckpoint {
  id: string;
  occurredAt: string;
  project: string;
  task: string;
  summary: string;
  lastAction: string;
  nextAction: string;
  confidence: number;
  keyActivities: Array<{
    timestamp?: string;
    app: string;
    action: string;
    subject?: string;
  }>;
}

export interface VoiceHistoryResult {
  query: string;
  summaries: VoiceCheckpoint[];
}

export interface VoiceBootstrapContext {
  current: VoiceCheckpoint | null;
  recent: VoiceCheckpoint[];
}
