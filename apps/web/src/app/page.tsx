import { ActivityStatus } from "../components/ActivityStatus";
import { PrivacyIndicator } from "../components/PrivacyIndicator";
import { RecordingControls } from "../components/RecordingControls";
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
<<<<<<< HEAD
      <VoiceOrb />
      <RecordingControls />
      {checkpoint ? <SessionCard checkpoint={checkpoint} /> : <p className="muted">No activity profile has been captured yet.</p>}
=======
      <VoiceOrb checkpoint={checkpoint} />
      <SessionCard checkpoint={checkpoint} />
>>>>>>> main
      <ResumeButton />
      <PrivacyIndicator />
    </main>
  );
}
