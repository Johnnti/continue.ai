import { z } from "zod";

export const ResumeTargetSchema = z.object({
  type: z.enum(["url", "file", "app"]),
  value: z.string().min(1),
  label: z.string().optional()
});

export const MemoryFactSchema = z.object({
  type: z.enum(["url", "file", "app", "text"]),
  value: z.string().min(1),
  label: z.string().optional()
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
  resumeTargets: z.array(ResumeTargetSchema),
  confidence: z.number().min(0).max(1),
  sourceWindowMinutes: z.number().int().min(1),
  tags: z.array(z.string()).default([]),
  facts: z.array(MemoryFactSchema).default([]),
  context: z.array(z.string()).default([]),
  createdAt: z.string().optional(),
  updatedAt: z.string().optional()
});
