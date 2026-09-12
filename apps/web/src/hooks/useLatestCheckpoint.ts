"use client";

import { useEffect, useState } from "react";
import type { SessionCheckpoint } from "@continue/shared";

export function useLatestCheckpoint() {
  const [checkpoint, setCheckpoint] = useState<SessionCheckpoint | null>(null);

  useEffect(() => {
    fetch("/api/checkpoint")
      .then((response) => response.json())
      .then((data) => setCheckpoint(data.checkpoint))
      .catch(() => setCheckpoint(null));
  }, []);

  return checkpoint;
}
