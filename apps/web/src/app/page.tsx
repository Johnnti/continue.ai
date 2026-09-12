import { ActivityStatus } from "../components/ActivityStatus";
import { PrivacyIndicator } from "../components/PrivacyIndicator";
import { RecordingControls } from "../components/RecordingControls";
import { ResumeButton } from "../components/ResumeButton";
import { SessionCard } from "../components/SessionCard";
import { VoiceOrb } from "../components/VoiceOrb";
import { getLatestCheckpoint, searchMemory } from "../lib/api";

export default async function Page() {
  const checkpoint = await getLatestCheckpoint();
  const history = await searchMemory({ limit: 5 });

  return (
    <main>
      <h1>continue.ai</h1>
      <p className="muted">Local-first context resume assistant</p>
      <ActivityStatus state="returning" />
      <RecordingControls />
      {checkpoint ? <SessionCard checkpoint={checkpoint} /> : <p className="muted">No activity profile has been captured yet.</p>}
      <VoiceOrb checkpoint={checkpoint} />
      <SessionCard checkpoint={checkpoint} />
      <section className="card">
        <h2>Recent memory</h2>
        {history.length === 0 ? (
          <p className="muted">No saved checkpoints yet.</p>
        ) : (
          <ul>
            {history.map((item) => (
              <li key={item.id}>
                <strong>{item.project}</strong>: {item.currentTask} ({new Date(item.endedAt).toLocaleString()})
              </li>
            ))}
          </ul>
        )}
      </section>
      <ResumeButton />
      <PrivacyIndicator />
    </main>
  );
}
