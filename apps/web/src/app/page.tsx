import { ActivityStatus } from "../components/ActivityStatus";
import { PrivacyIndicator } from "../components/PrivacyIndicator";
import { ResumeButton } from "../components/ResumeButton";
import { SessionCard } from "../components/SessionCard";
import { VoiceOrb } from "../components/VoiceOrb";
import { getLatestCheckpoint } from "../lib/api";

export default async function Page() {
  const checkpoint = await getLatestCheckpoint();

  return (
    <main>
      <h1>continue.ai</h1>
      <p className="muted">Local-first context resume assistant</p>
      <ActivityStatus state="returning" />
      <VoiceOrb />
      <SessionCard checkpoint={checkpoint} />
      <ResumeButton />
      <PrivacyIndicator />
    </main>
  );
}
