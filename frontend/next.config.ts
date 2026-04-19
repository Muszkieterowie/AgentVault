import type { NextConfig } from "next";

// Pin Turbopack's workspace root to the frontend directory. Computed at
// runtime from process.cwd() so it works under both Next's CJS and ESM
// config loaders — `__dirname` is unreliable here because Next rewrites
// the module context when it transpiles this file.
const nextConfig: NextConfig = {
  turbopack: {
    root: process.cwd(),
  },
};

export default nextConfig;
