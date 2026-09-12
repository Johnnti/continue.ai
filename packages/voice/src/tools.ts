import { getCurrentContext, getLastSession } from "./agentContext";
import { resumeWorkspace } from "@continue/workspace";

export const voiceTools = {
  getLastSession,
  getCurrentContext,
  async resumeWorkspace() {
    const checkpoint = await getCurrentContext();
    return resumeWorkspace(checkpoint.resumeTargets);
  }
};
