"use client";

import {
  ConversationProvider,
  useConversationControls,
  useConversationStatus,
} from "@elevenlabs/react";

const AGENT_ID = "agent_6701m2aempkqeh7a0922tc0b0krr";

type Checkpoint = {
  project?: string;
  task?: string;
  last_action?: string;
  next_action?: string;
};

function VoiceOrbInner({ checkpoint }: { checkpoint: Checkpoint }) {
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
          task: checkpoint?.task ?? "your previous task",
          last_action:
            checkpoint?.last_action ?? "working on your computer",
          next_action:
            checkpoint?.next_action ?? "continue where you left off",
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
  checkpoint: Checkpoint;
}) {
  return (
    <ConversationProvider>
      <VoiceOrbInner checkpoint={checkpoint} />
    </ConversationProvider>
  );
}
