import { createServerClient } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

import type { Database } from "@workspace/database"

import { publicConfig } from "./config"

type CookieToSet = Readonly<{
  name: string
  value: string
  options: Record<string, unknown>
}>

export type CookieBridge = Readonly<{
  getAll: () => { name: string; value: string }[]
  setAll: (
    cookiesToSet: CookieToSet[],
    cacheHeaders?: Record<string, string>
  ) => void
}>

export type SessionRefresh = (bridge: CookieBridge) => Promise<void>

async function refreshWithSupabase(bridge: CookieBridge): Promise<void> {
  const config = publicConfig()
  const client = createServerClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    { cookies: bridge as never }
  )
  // `getClaims` valida la firma y, de paso, renueva el token si venciÃ³.
  await client.auth.getClaims()
}

/**
 * Renueva la sesiÃ³n y devuelve la respuesta con las cookies actualizadas.
 *
 * El proxy es optimista: nunca es el lÃ­mite de autorizaciÃ³n. Si el refresh
 * falla, la request sigue y quien decide es el Server Component o la Server
 * Action, que verifican identidad por su cuenta.
 */
export async function updateSession(
  request: NextRequest,
  refresh: SessionRefresh = refreshWithSupabase
): Promise<NextResponse> {
  let response = NextResponse.next({ request })

  const bridge: CookieBridge = {
    getAll: () => request.cookies.getAll(),
    setAll: (cookiesToSet, cacheHeaders) => {
      for (const { name, value } of cookiesToSet) {
        request.cookies.set(name, value)
      }
      response = NextResponse.next({ request })
      for (const { name, options, value } of cookiesToSet) {
        response.cookies.set(name, value, options)
      }
      // Una respuesta que setea cookies de sesiÃ³n no puede quedar en una cache
      // compartida: si se cachea, un usuario recibe el token de otro.
      for (const [key, value] of Object.entries(cacheHeaders ?? {})) {
        response.headers.set(key, value)
      }
    },
  }

  try {
    await refresh(bridge)
  } catch {
    return response
  }

  return response
}
