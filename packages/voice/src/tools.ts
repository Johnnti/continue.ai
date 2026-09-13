import {
  getCheckpointContext,
  getCurrentContext,
  getLastSession,
  searchPastSummaries
} from "./agentContext";
import { toVoiceCheckpoint } from "./elevenlabs";

export const voiceTools = {
  async get_last_session() {
    const checkpoint = await getLastSession();
    return JSON.stringify({
      checkpoint: checkpoint ? toVoiceCheckpoint(checkpoint) : null
    });
  },
  async get_session_context(parameters: { checkpoint_id?: string } = {}) {
    const checkpoint = await getCheckpointContext(parameters.checkpoint_id);
    return JSON.stringify({
      checkpoint: checkpoint ? toVoiceCheckpoint(checkpoint) : null
    });
  },
  async search_past_summaries(parameters: { query?: string; limit?: number } = {}) {
    const result = await searchPastSummaries(parameters.query ?? "", parameters.limit);
    return JSON.stringify(result);
  },
  async request_resume_workspace() {
    const checkpoint = await getCurrentContext();
    return JSON.stringify({
      ok: Boolean(checkpoint),
      checkpointId: checkpoint?.id ?? null,
      confirmationRequired: true,
      message: checkpoint
        ? "Ask the user to confirm the workspace items in the Continue interface. Nothing has been opened yet."
        : "No activity profile is available yet."
    });
  }
};
