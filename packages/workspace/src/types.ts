import type { ResumeTarget } from "@continue/shared";

export interface ResumeResult {
  attempted: number;
  restored: number;
  failures: string[];
  targets: ResumeTarget[];
}
