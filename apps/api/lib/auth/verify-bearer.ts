import type { Authenticator } from "@workspace/api"

export type VerifiedClaims = Readonly<{ sub?: unknown }>

/**
 * Devuelve los claims solo si la firma del token es válida. Un token inválido
 * o vencido devuelve `undefined` (401); lanzar queda reservado para una falla
 * de infraestructura, que el wrapper traduce a 503.
 */
export type ClaimsVerifier = (
  token: string
) => Promise<VerifiedClaims | undefined>

export function readBearerToken(request: Request): string | undefined {
  const header = request.headers.get("authorization")
  if (!header) return undefined
  const match = /^bearer\s+(\S+)$/i.exec(header.trim())
  return match?.[1]
}

export function createBearerAuthenticator(
  verify: ClaimsVerifier
): Authenticator<Request> {
  return async (request) => {
    const token = readBearerToken(request)
    if (!token) return undefined

    const claims = await verify(token)
    const sub = claims?.sub
    // La identidad sale únicamente del `sub` verificado. Ningún claim de rol o
    // metadata del JWT decide pertenencia a un tenant: eso lo resuelve RLS
    // contra las filas de membresía.
    if (typeof sub !== "string" || sub.length === 0) return undefined

    return { credential: token, id: sub }
  }
}
