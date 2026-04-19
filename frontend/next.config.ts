import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Pin Turbopack/Next's workspace root to this directory so it does not
  // accidentally latch onto a parent lockfile when the repo is nested in a
  // larger monorepo. Vercel honours this too.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
