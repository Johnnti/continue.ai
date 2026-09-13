import { z } from "zod";

export const ResumeTargetSchema = z.object({
  type: z.enum(["url", "file", "app"]),
  value: z.string().min(1),
  label: z.string().min(1).nullable().transform((value) => value ?? undefined).optional()
});

export const KeyActivitySchema = z.object({
  timestamp: z.string().min(1).nullable().transform((value) => value ?? undefined).optional(),
  app: z.string().min(1),
  action: z.string().min(1),
  subject: z.string().min(1).nullable().transform((value) => value ?? undefined).optional(),
  evidence: z.enum(["observed", "inferred"])
});

/**
 * The model-facing portion of a checkpoint. Keep this separate from the
 * persisted schema because the server, rather than the model, owns identity,
 * timestamps, and source counters.
 */
export const SessionSummarySchema = z.object({
  project: z.string().min(1),
  currentTask: z.string().min(1),
  summary: z.string().min(1),
  lastAction: z.string().min(1),
  nextAction: z.string().min(1),
  keyActivities: z.array(KeyActivitySchema).max(8),
  resumeTargets: z.array(ResumeTargetSchema),
  confidence: z.number().min(0).max(1)
}).strict();

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
