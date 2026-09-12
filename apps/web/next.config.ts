import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: [
    "@continue/shared",
    "@continue/screenpipe",
    "@continue/context-engine",
    "@continue/memory",
    "@continue/voice",
    "@continue/workspace"
  ]
};

export default nextConfig;
