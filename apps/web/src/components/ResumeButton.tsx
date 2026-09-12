"use client";

import { useState } from "react";

export function ResumeButton() {
  const [message, setMessage] = useState<string>("");

  return (
    <div className="card">
      <button
        onClick={async () => {
          const response = await fetch("/api/resume", { method: "POST" });
          const body = await response.json();
          setMessage(`Restored ${body.restored}/${body.attempted} targets`);
        }}
      >
        Resume Workspace
      </button>
      {message ? <p className="muted">{message}</p> : null}
    </div>
  );
}
