"use client";

import { useEffect, useState } from "react";

export function useElevenLabs() {
  const [status, setStatus] = useState("unconfigured");

  useEffect(() => {
    if (process.env.NEXT_PUBLIC_ELEVENLABS_ENABLED === "true") {
      setStatus("configured");
    }
  }, []);

  return status;
}
