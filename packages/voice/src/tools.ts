import { getCurrentContext, getLastSession } from "./agentContext";
import { resumeWorkspace } from "@continue/workspace";

export const voiceTools = {
  getLastSession,
  getCurrentContext,
  async resumeWorkspace() {
    const checkpoint = await getCurrentContext();
    if (!checkpoint) {
      return { ok: false, message: "No activity profile is available yet" };
    }
    return resumeWorkspace(checkpoint.resumeTargets);
  }
};
