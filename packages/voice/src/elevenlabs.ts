import type { SessionCheckpoint } from "@continue/shared";

export function buildReturnBriefing(checkpoint: SessionCheckpoint): string {
  return [
    "Welcome back.",
    "",
    `You were working on ${checkpoint.project}.`,
    "",
    `You were ${checkpoint.currentTask}, and the last thing you did was ${checkpoint.lastAction}.`,
    "",
    `Your next step was ${checkpoint.nextAction}.`,
    "",
    "Would you like me to resume your workspace?"
  ].join("\n");
}

export async function sendCheckpointToElevenLabs(checkpoint: SessionCheckpoint): Promise<{ ok: boolean; message: string }> {
  if (!process.env.ELEVENLABS_API_KEY || !process.env.ELEVENLABS_AGENT_ID) {
    return {
      ok: true,
      message: "ElevenLabs keys not configured. Running in mock mode."
    };
  }

  return {
    ok: true,
    message: `Prepared checkpoint ${checkpoint.id} for ElevenLabs agent ${process.env.ELEVENLABS_AGENT_ID}`
  };
}
