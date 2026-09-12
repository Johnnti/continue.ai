"use client";

import {
  ConversationProvider,
  useConversationControls,
  useConversationStatus,
} from "@elevenlabs/react";
import type { SessionCheckpoint } from "@continue/shared";

const AGENT_ID = "agent_6701m2aempkqeh7a0922tc0b0krr";

function VoiceOrbInner({ checkpoint }: { checkpoint: SessionCheckpoint | null }) {
  const { startSession, endSession } = useConversationControls();
  const { status } = useConversationStatus();

  async function handleClick() {
    try {
      if (status === "connected") {
        await endSession();
        return;
      }

      await navigator.mediaDevices.getUserMedia({
        audio: true,
      });

      await startSession({
        agentId: AGENT_ID,
        dynamicVariables: {
          project: checkpoint?.project ?? "Continue",
          task: checkpoint?.currentTask ?? "your previous task",
          last_action: checkpoint?.lastAction ?? "working on your computer",
          next_action: checkpoint?.nextAction ?? "continue where you left off",
        },
      });
    } catch (error) {
      console.error("Failed to start Continue:", error);
    }
  }

  return (
    <button className="card" onClick={handleClick}>
      🔵 {status === "connected" ? "Continue is listening..." : "Talk to Continue"}
    </button>
  );
}

export function VoiceOrb({
  checkpoint,
}: {
  checkpoint: SessionCheckpoint | null;
}) {
  return (
    <ConversationProvider>
      <VoiceOrbInner checkpoint={checkpoint} />
    </ConversationProvider>
  );
}
