import type { SessionMemory } from "@continue/shared";
import type { MemoryQuery } from "./types";

export function buildMemorySearchIndex(memories: SessionMemory[]) {
  return memories.map((memory) => ({
    memory,
    haystack: [
      memory.project,
      memory.currentTask,
      memory.summary,
      memory.lastAction,
      memory.nextAction,
      ...(memory.tags ?? []),
      ...(memory.context ?? []),
      ...(memory.facts ?? []).map((fact) => `${fact.type}:${fact.value}`)
    ]
      .join(" ")
      .toLowerCase()
  }));
}

export function searchMemory(memories: SessionMemory[], query: MemoryQuery = {}): SessionMemory[] {
  const text = (query.text ?? "").trim().toLowerCase();
  const tags = (query.tags ?? []).map((tag) => tag.toLowerCase());

  return buildMemorySearchIndex(memories)
    .filter(({ memory, haystack }) => {
      const projectMatches = !query.project || memory.project.toLowerCase().includes(query.project.toLowerCase());
      const tagMatches = tags.length === 0 || tags.every((tag) => (memory.tags ?? []).some((memoryTag) => memoryTag.toLowerCase() === tag));
      const textMatches = !text || haystack.includes(text);
      return projectMatches && tagMatches && textMatches;
    })
    .map(({ memory }) => memory)
    .slice(0, query.limit ?? 10);
}
