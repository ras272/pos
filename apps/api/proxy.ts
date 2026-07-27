import { NextResponse, type NextRequest } from "next/server"

import { createCors } from "./lib/http/cors"
import { apiSecurityHeaders, type Environment } from "./lib/security/headers"

function environment(): Environment {
  if (process.env.NODE_ENV === "production") return "production"
  if (process.env.NODE_ENV === "test") return "test"
  return "development"
}

function allowedOrigins(): string[] {
  return [process.env.ADMIN_ORIGIN, process.env.CAJA_ORIGIN].filter(
    (origin): origin is string => Boolean(origin)
  )
}

function harden(headers: Headers): void {
  for (const { key, value } of apiSecurityHeaders(environment())) {
    headers.set(key, value)
  }
}

// El CORS se resuelve acá y no en cada route: el checker de entrypoints exige
// que el export HTTP sea una llamada directa al wrapper compartido, así que
// envolverlo en la route rompería esa garantía.
export function proxy(request: NextRequest): Response {
  const cors = createCors({
    allowedHeaders: ["Authorization", "Content-Type"],
    allowedMethods: ["GET", "POST", "OPTIONS"],
    allowedOrigins: allowedOrigins(),
  })

  const preflight = cors.preflight(request)
  if (preflight) {
    harden(preflight.headers)
    return preflight
  }

  const response = NextResponse.next()
  cors.decorate(response.headers, request)
  harden(response.headers)
  return response
}

export const config = {
  matcher: "/api/:path*",
}
