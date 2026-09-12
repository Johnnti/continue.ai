import type { SessionCheckpoint } from "@continue/shared";

export function SessionCard({ checkpoint }: { checkpoint: SessionCheckpoint }) {
  return (
    <section className="card">
      <h2>Welcome back</h2>
      <p><strong>Project:</strong> {checkpoint.project}</p>
      <p><strong>Previous task:</strong> {checkpoint.currentTask}</p>
      <p><strong>Last action:</strong> {checkpoint.lastAction}</p>
      <p><strong>Next action:</strong> {checkpoint.nextAction}</p>
      <p><strong>Summary:</strong> {checkpoint.summary}</p>
      {checkpoint.tags?.length ? (
        <p><strong>Tags:</strong> {checkpoint.tags.join(", ")}</p>
      ) : null}
      {checkpoint.facts?.length ? (
        <ul>
          {checkpoint.facts.slice(0, 3).map((fact) => (
            <li key={`${fact.type}:${fact.value}`}>{fact.type}: {fact.value}</li>
          ))}
        </ul>
      ) : null}
      <p className="muted">Source window: {checkpoint.sourceWindowMinutes} minutes</p>
    </section>
  );
}
