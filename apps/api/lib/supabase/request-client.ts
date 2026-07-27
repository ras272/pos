import { createClient, type SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@workspace/database"
import type { PublicEnv } from "@workspace/env/public"

import type { ClaimsVerifier, VerifiedClaims } from "../auth/verify-bearer"

export type RequestSupabaseClient = SupabaseClient<Database>

/**
 * Cliente con alcance de usuario: lleva la clave publicable y el bearer ya
 * verificado, nada mÃ¡s. RLS sigue siendo el lÃ­mite de tenant, asÃ­ que este
 * cliente no puede ver mÃ¡s de lo que la membresÃ­a del usuario permite.
 */
export function createRequestClient(
  config: PublicEnv,
  accessToken: string
): RequestSupabaseClient {
  return createClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    }
  )
}

export function createSupabaseClaimsVerifier(
  config: PublicEnv
): ClaimsVerifier {
  const client = createClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey,
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    }
  )

  return async (token) => {
    // `getClaims` valida la firma contra las claves pÃºblicas publicadas.
    // `getSession` no sirve acÃ¡: no revalida nada y es falsificable.
    const { data, error } = await client.auth.getClaims(token)
    if (error || !data) return undefined
    return data.claims as VerifiedClaims
  }
}
