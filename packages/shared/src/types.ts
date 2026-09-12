export interface ActivityInteraction {
  timestamp: string;
  type: "click" | "app_switch" | "scroll";
  appName?: string;
  windowTitle?: string;
  x?: number;
  y?: number;
  elementRole?: string;
  elementLabel?: string;
}

export interface ActivityEvent {
  timestamp: string;
  appName?: string;
  windowTitle?: string;
  text?: string;
  screenshotBase64?: string;
  displayName?: string;
  displayId?: number;
  width?: number;
  height?: number;
  url?: string;
  filePath?: string;
  durationSeconds?: number;
  screenshotMimeType?: "image/jpeg" | "image/png";
  focusedElementRole?: string;
  focusedElementLabel?: string;
  interactions?: ActivityInteraction[];
}

export interface ResumeTarget {
  type: "url" | "file" | "app";
  value: string;
  label?: string;
}

export interface KeyActivity {
  timestamp?: string;
  app: string;
  action: string;
  subject?: string;
  evidence: "observed" | "inferred";
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
  keyActivities?: KeyActivity[];
  resumeTargets: ResumeTarget[];
  confidence: number;
  sourceWindowMinutes: number;
  sourceEventCount?: number;
}

export type ContinueState =
  | "observing"
  | "away"
  | "returning"
  | "briefing"
  | "resuming";
