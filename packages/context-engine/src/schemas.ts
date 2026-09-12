import { z } from "zod";

export const ResumeTargetSchema = z.object({
  type: z.enum(["url", "file", "app"]),
  value: z.string().min(1),
  label: z.string().optional()
});

export const KeyActivitySchema = z.object({
  timestamp: z.string().optional(),
  app: z.string().min(1),
  action: z.string().min(1),
  subject: z.string().min(1).optional(),
  evidence: z.enum(["observed", "inferred"])
});

export const SessionCheckpointSchema = z.object({
  id: z.string().min(1),
  startedAt: z.string().optional(),
  endedAt: z.string(),
  project: z.string().min(1),
  currentTask: z.string().min(1),
  summary: z.string().min(1),
  lastAction: z.string().min(1),
  nextAction: z.string().min(1),
  keyActivities: z.array(KeyActivitySchema).max(8).optional(),
  resumeTargets: z.array(ResumeTargetSchema),
  confidence: z.number().min(0).max(1),
  sourceWindowMinutes: z.number().int().min(1),
  sourceEventCount: z.number().int().min(1).optional()
});
