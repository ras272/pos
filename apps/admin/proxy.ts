import type { NextRequest } from "next/server"

import { publicConfig } from "./lib/supabase/config"
import { updateSession } from "./lib/supabase/proxy"
import {
  contentSecurityPolicy,
  createNonce,
  hardeningHeaders,
  type Environment,
} from "./lib/security/csp"

function environment(): Environment {
  if (process.env.NODE_ENV === "production") return "production"
  if (process.env.NODE_ENV === "test") return "test"
  return "development"
}

function connectSrc(): string[] {
  const origins = [new URL(publicConfig().supabaseUrl).origin]
  const apiUrl = process.env.NEXT_PUBLIC_API_URL
  if (apiUrl) origins.push(new URL(apiUrl).origin)
  return origins
}

export async function proxy(request: NextRequest) {
  const nonce = createNonce()
  const policy = contentSecurityPolicy({
    connectSrc: connectSrc(),
    environment: environment(),
    nonce,
  })

  // Next lee el nonce del encabezado CSP de la *request* para aplicarlo a sus
  // propios scripts, así que la política viaja en los dos sentidos.
  const response = await updateSession(request, {
    requestHeaders: {
      "Content-Security-Policy": policy,
      "x-nonce": nonce,
    },
  })

  response.headers.set("Content-Security-Policy", policy)
  for (const { key, value } of hardeningHeaders(environment())) {
    response.headers.set(key, value)
  }

  return response
}

export const config = {
  matcher: [
    {
      /*
       * Todo salvo estáticos. Los `_next/data` igual pasan por acá: Next los
       * incluye a propósito para que proteger una página no deje su ruta de
       * datos abierta.
       */
      source: "/((?!_next/static|_next/image|favicon.ico).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
}
