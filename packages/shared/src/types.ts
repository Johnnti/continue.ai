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
  idleSeconds?: number;
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

export interface MemoryFact {
  type: "url" | "file" | "app" | "text";
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
  tags?: string[];
  facts?: MemoryFact[];
  context?: string[];
  createdAt?: string;
  updatedAt?: string;
}

export type SessionMemory = SessionCheckpoint;

export type ContinueState =
  | "observing"
  | "away"
  | "returning"
  | "briefing"
  | "resuming";

export type CheckpointTrigger = "automatic" | "manual" | "automaticAndManual";

export interface TrackingSchedulePolicy {
  isEnabled: boolean;
  startHour: number;
  endHour: number;
}

export interface ActivityTrackingPolicy {
  captureEnabled: boolean;
  summariesEnabled: boolean;
  checkpointTrigger: CheckpointTrigger;
  idleThresholdMinutes: number;
  observationWindowMinutes: number;
  schedule: TrackingSchedulePolicy;
  excludedApplications: string[];
  checkpointRetentionDays: number;
  screenpipeRetentionDays: number;
}

export type RuntimePhase = "observing" | "away" | "returning";
export type RuntimeCaptureStatus = "recording" | "paused" | "unavailable";

export interface RuntimeStatusRecord {
  phase: RuntimePhase;
  captureStatus: RuntimeCaptureStatus;
  statusMessage: string;
  lastActivityAt: string | null;
  heartbeatAt: string;
}

export const DEFAULT_ACTIVITY_TRACKING_POLICY: ActivityTrackingPolicy = {
  captureEnabled: true,
  summariesEnabled: true,
  checkpointTrigger: "automaticAndManual",
  idleThresholdMinutes: 4,
  observationWindowMinutes: 30,
  schedule: {
    isEnabled: false,
    startHour: 9,
    endHour: 17
  },
  excludedApplications: [],
  checkpointRetentionDays: 7,
  screenpipeRetentionDays: 0
};
