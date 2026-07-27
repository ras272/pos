import type { NextConfig } from "next"

const nextConfig: NextConfig = {
  transpilePackages: [
    "@workspace/api",
    "@workspace/database",
    "@workspace/env",
  ],
}

export default nextConfig
