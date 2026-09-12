import { loadEnvConfig } from "@next/env";
import path from "node:path";
import type { NextConfig } from "next";

// Next only discovers env files inside apps/web by default. This workspace keeps
// its private local configuration at the repository root, so load it before any
// route modules read process.env.
loadEnvConfig(
  path.resolve(process.cwd(), "../.."),
  process.env.NODE_ENV !== "production",
  console,
  true,
);

const nextConfig: NextConfig = {
  transpilePackages: [
    "@continue/shared",
    "@continue/screenpipe",
    "@continue/context-engine",
    "@continue/memory",
    "@continue/workspace"
  ]
};

export default nextConfig;
