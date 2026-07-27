import { NextResponse, type NextRequest } from "next/server"

import { createCors } from "./lib/http/cors"

function allowedOrigins(): string[] {
  return [process.env.ADMIN_ORIGIN, process.env.CAJA_ORIGIN].filter(
    (origin): origin is string => Boolean(origin)
  )
}

// El CORS se resuelve acÃ¡ y no en cada route: el checker de entrypoints exige
// que el export HTTP sea una llamada directa al wrapper compartido, asÃ­ que
// envolverlo en la route romperÃ­a esa garantÃ­a.
export function proxy(request: NextRequest): Response {
  const cors = createCors({
    allowedHeaders: ["Authorization", "Content-Type"],
    allowedMethods: ["GET", "POST", "OPTIONS"],
    allowedOrigins: allowedOrigins(),
  })

  const preflight = cors.preflight(request)
  if (preflight) return preflight

  const response = NextResponse.next()
  cors.decorate(response.headers, request)
  return response
}

export const config = {
  matcher: "/api/:path*",
}
