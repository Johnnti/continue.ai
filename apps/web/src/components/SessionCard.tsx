import type { SessionCheckpoint } from "@continue/shared";

export function SessionCard({ checkpoint }: { checkpoint: SessionCheckpoint }) {
  return (
    <section className="card">
      <h2>Welcome back</h2>
      <p><strong>Project:</strong> {checkpoint.project}</p>
      <p><strong>Previous task:</strong> {checkpoint.currentTask}</p>
      <p><strong>Activity summary:</strong> {checkpoint.summary}</p>
      {checkpoint.keyActivities && checkpoint.keyActivities.length > 0 && (
        <div>
          <strong>Key activities:</strong>
          <ol>
            {checkpoint.keyActivities.map((activity, index) => (
              <li key={`${activity.timestamp ?? index}-${activity.app}-${activity.action}`}>
                {activity.action}{activity.subject ? ` — ${activity.subject}` : ""} ({activity.app})
              </li>
            ))}
          </ol>
        </div>
      )}
      <p><strong>Last action:</strong> {checkpoint.lastAction}</p>
      <p><strong>Next action:</strong> {checkpoint.nextAction}</p>
      <p className="muted">Source window: {checkpoint.sourceWindowMinutes} minutes</p>
    </section>
  );
}
