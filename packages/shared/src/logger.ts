export const logger = {
  info: (...args: unknown[]) => console.log("[continue.ai]", ...args),
  warn: (...args: unknown[]) => console.warn("[continue.ai]", ...args),
  error: (...args: unknown[]) => console.error("[continue.ai]", ...args)
};
