"use client";

import { useEffect, useState } from "react";
import type { KeyActivity } from "@continue/shared";

interface RecordingStatus {
  recording: boolean;
  processing: boolean;
  capturesProcessed: number;
  pendingCaptures: number;
  sessionStartedAt: string | null;
  latestSummaryAt: string | null;
  latestCapture: {
    timestamp: string;
    appName?: string;
    windowTitle?: string;
    displayName?: string;
    displayId?: number;
  } | null;
  lastError: string | null;
}

export function RecordingControls() {
  const [status, setStatus] = useState<RecordingStatus>({
    recording: false,
    processing: false,
    capturesProcessed: 0,
    pendingCaptures: 0,
    sessionStartedAt: null,
    latestSummaryAt: null,
    latestCapture: null,
    lastError: null
  });
  const [paragraph, setParagraph] = useState("");
  const [keyActivities, setKeyActivities] = useState<KeyActivity[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function refreshStatus() {
    try {
      const response = await fetch("/api/record/status", { cache: "no-store" });
      const nextStatus = await response.json() as RecordingStatus & { error?: string };
      if (!response.ok) throw new Error(nextStatus.error ?? "Unable to read recording status");
      setStatus(nextStatus);
      if (nextStatus.lastError) setError(nextStatus.lastError);
    } catch (statusError) {
      setError(statusError instanceof Error ? statusError.message : "Unable to read recording status");
    }
  }

  useEffect(() => {
    void refreshStatus();
    const interval = window.setInterval(() => void refreshStatus(), 5000);
    return () => window.clearInterval(interval);
  }, []);

  async function start() {
    setError("");
    setParagraph("");
    setKeyActivities([]);
    try {
      const response = await fetch("/api/record/start", { method: "POST" });
      const result = await response.json() as RecordingStatus & { error?: string };
      setStatus(result);
      if (!response.ok) setError(result.error ?? "Unable to start recording");
    } catch (startError) {
      setError(startError instanceof Error ? startError.message : "Unable to start recording");
    }
  }

  async function stop() {
    setError("");
    try {
      const response = await fetch("/api/record/stop", { method: "POST" });
      const result = await response.json() as RecordingStatus & { error?: string };
      setStatus(result);
      if (!response.ok) setError(result.error ?? "Unable to stop recording");
    } catch (stopError) {
      setError(stopError instanceof Error ? stopError.message : "Unable to stop recording");
    }
  }

  async function generateSummary() {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/summary", { method: "POST" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Unable to generate summary");
      setParagraph(result.summary);
      setKeyActivities(result.checkpoint?.keyActivities ?? []);
      await refreshStatus();
    } catch (summaryError) {
      setError(summaryError instanceof Error ? summaryError.message : "Unable to generate summary");
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="card">
      <h2>Activity recording</h2>
      <p className="muted">
        {status.recording
          ? `Recording: ${status.capturesProcessed} captured, ${status.pendingCaptures} awaiting summary`
          : status.processing
            ? "Finishing the latest activity summary…"
          : "Recording stopped"}
      </p>
      {status.latestCapture && (
        <p className="muted">
          Latest capture: {status.latestCapture.appName ?? "Unknown app"}
          {status.latestCapture.windowTitle ? ` — ${status.latestCapture.windowTitle}` : ""}
          {status.latestCapture.displayName ? ` on ${status.latestCapture.displayName}` : ""}
        </p>
      )}
      <button onClick={start} disabled={status.recording || status.processing}>Start</button>{" "}
      <button onClick={stop} disabled={!status.recording}>Stop</button>{" "}
      <button onClick={generateSummary} disabled={loading}>
        {loading ? "Loading..." : "Show latest summary"}
      </button>
      {paragraph && <p><strong>Paragraph summary:</strong> {paragraph}</p>}
      {keyActivities.length > 0 && (
        <div>
          <strong>Key activities:</strong>
          <ol>
            {keyActivities.map((activity, index) => (
              <li key={`${activity.timestamp ?? index}-${activity.app}-${activity.action}`}>
                {activity.action}{activity.subject ? ` — ${activity.subject}` : ""} ({activity.app})
              </li>
            ))}
          </ol>
        </div>
      )}
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
