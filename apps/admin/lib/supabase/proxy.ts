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

export type UpdateSessionOptions = Readonly<{
  refresh?: SessionRefresh
  /** Encabezados que la app tiene que ver, por ejemplo el nonce de la CSP. */
  requestHeaders?: Record<string, string>
}>

async function refreshWithSupabase(bridge: CookieBridge): Promise<void> {
  const config = publicConfig()
  const client = createServerClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    { cookies: bridge as never }
  )
  // `getClaims` valida la firma y, de paso, renueva el token si venció.
  await client.auth.getClaims()
}

/**
 * Renueva la sesión y devuelve la respuesta con las cookies actualizadas.
 *
 * El proxy es optimista: nunca es el límite de autorización. Si el refresh
 * falla, la request sigue y quien decide es el Server Component o la Server
 * Action, que verifican identidad por su cuenta.
 */
export async function updateSession(
  request: NextRequest,
  options: UpdateSessionOptions = {}
): Promise<NextResponse> {
  const refresh = options.refresh ?? refreshWithSupabase

  // Se reconstruye en cada llamada porque `request.cookies.set` muta el
  // encabezado `cookie`: clonar antes dejaría a la app viendo el token viejo.
  const forwardedHeaders = () => {
    const headers = new Headers(request.headers)
    for (const [key, value] of Object.entries(options.requestHeaders ?? {})) {
      headers.set(key, value)
    }
    return headers
  }

  let response = NextResponse.next({ request: { headers: forwardedHeaders() } })

  const bridge: CookieBridge = {
    getAll: () => request.cookies.getAll(),
    setAll: (cookiesToSet, cacheHeaders) => {
      for (const { name, value } of cookiesToSet) {
        request.cookies.set(name, value)
      }
      response = NextResponse.next({
        request: { headers: forwardedHeaders() },
      })
      for (const { name, options: cookieOptions, value } of cookiesToSet) {
        response.cookies.set(name, value, cookieOptions)
      }
      // Una respuesta que setea cookies de sesión no puede quedar en una cache
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
