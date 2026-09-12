export interface ActivityEvent {
  timestamp: string;
  appName?: string;
  windowTitle?: string;
  text?: string;
  url?: string;
  filePath?: string;
  durationSeconds?: number;
}

export interface ResumeTarget {
  type: "url" | "file" | "app";
  value: string;
  label?: string;
}

export interface SessionCheckpoint {
  id: string;
  startedAt?: string;
  endedAt: string;
  project: string;
  currentTask: string;
  summary: string;
  lastAction: string;
  nextAction: string;
  resumeTargets: ResumeTarget[];
  confidence: number;
  sourceWindowMinutes: number;
}

export type ContinueState =
  | "observing"
  | "away"
  | "returning"
  | "briefing"
  | "resuming";
