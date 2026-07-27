import type { NextConfig } from "next"

import { webSecurityHeaders, type Environment } from "./lib/security/headers"

function environment(): Environment {
  if (process.env.NODE_ENV === "production") return "production"
  if (process.env.NODE_ENV === "test") return "test"
  return "development"
}

const nextConfig: NextConfig = {
  transpilePackages: ["@workspace/ui"],
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [...webSecurityHeaders(environment())],
      },
    ]
  },
}

export default nextConfig
