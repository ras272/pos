import "server-only"

import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"

import type { Database } from "@workspace/database"

import { publicConfig } from "./config"

/**
 * Cliente de servidor con las cookies de la request. RLS sigue siendo el
 * lÃ­mite de tenant: este cliente no ve mÃ¡s de lo que la membresÃ­a permite.
 */
export async function createServerSupabaseClient() {
  const config = publicConfig()
  const cookieStore = await cookies()

  return createServerClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, options, value } of cookiesToSet) {
              cookieStore.set(name, value, options)
            }
          } catch {
            // Un Server Component no puede escribir cookies. El refresh de
            // sesiÃ³n lo hace el proxy, asÃ­ que acÃ¡ no hay nada que salvar.
          }
        },
      },
    }
  )
}
