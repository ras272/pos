import type { Authenticator } from "@workspace/api"

export type SessionClaims = Readonly<{ sub?: unknown }>

/** Devuelve claims solo si la firma del token se validó. */
export type ClaimsReader = () => Promise<SessionClaims | undefined>

export type ClaimsCapableClient = {
  auth: {
    getClaims: () => Promise<{
      data?: { claims?: unknown } | null
      error?: unknown
    }>
  }
}

/**
 * `getClaims` valida la firma del JWT contra las claves públicas publicadas.
 * `getSession` se lee de almacenamiento local sin revalidar, así que jamás
 * puede decidir una autorización de servidor.
 */
export function createClaimsReader(client: ClaimsCapableClient): ClaimsReader {
  return async () => {
    const { data, error } = await client.auth.getClaims()
    if (error || !data?.claims) return undefined
    return data.claims as SessionClaims
  }
}

export function createIdentityAuthenticator(
  readClaims: ClaimsReader
): Authenticator<void> {
  return async () => {
    const claims = await readClaims()
    const sub = claims?.sub
    // La identidad es el `sub` verificado y nada más. Rol y tenant salen de las
    // filas de membresía vía RLS, nunca de metadata del JWT.
    if (typeof sub !== "string" || sub.length === 0) return undefined
    return { id: sub }
  }
}
