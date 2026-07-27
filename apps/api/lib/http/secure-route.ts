import type { AuditSink, Authenticator, RateLimiter } from "@workspace/api"
import { parsePublicEnv, type PublicEnv } from "@workspace/env/public"

import { createVercelAudit } from "../audit/vercel-audit"
import { createBearerAuthenticator } from "../auth/verify-bearer"
import {
  createPlatformLimiter,
  createRuntimeLimiter,
} from "../rate-limit/runtime-limiter"
import {
  createRequestClient,
  createSupabaseClaimsVerifier,
  type RequestSupabaseClient,
} from "../supabase/request-client"

export type RouteSecurity = Readonly<{
  audit: AuditSink
  authenticate: Authenticator<Request>
  createScopedClient: (actor: {
    credential?: string
  }) => Promise<RequestSupabaseClient | undefined>
  environment: "development" | "production" | "test"
  rateLimit: RateLimiter
}>

export function securityEnvironment(): RouteSecurity["environment"] {
  if (process.env.NODE_ENV === "production") return "production"
  if (process.env.NODE_ENV === "test") return "test"
  return "development"
}

// La configuraciÃ³n se resuelve en la primera request, no al importar el mÃ³dulo:
// asÃ­ un build sin variables no revienta, pero una request sin ellas falla.
let cachedConfig: PublicEnv | undefined
function config(): PublicEnv {
  cachedConfig ??= parsePublicEnv({
    SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  })
  return cachedConfig
}

/**
 * FÃ¡brica fina de configuraciÃ³n. No define wrappers propios: devuelve las
 * dependencias que `defineAuthenticatedRoute` necesita, para que el checker de
 * entrypoints siga viendo la llamada directa al wrapper compartido.
 */
export function routeSecurity(
  overrides: Partial<RouteSecurity> = {}
): RouteSecurity {
  const environment = overrides.environment ?? securityEnvironment()

  return {
    audit: overrides.audit ?? createVercelAudit(),

    authenticate:
      overrides.authenticate ??
      createBearerAuthenticator(async (token) =>
        createSupabaseClaimsVerifier(config())(token)
      ),

    createScopedClient:
      overrides.createScopedClient ??
      (async (actor) =>
        actor.credential
          ? createRequestClient(config(), actor.credential)
          : undefined),

    environment,

    rateLimit:
      overrides.rateLimit ??
      createRuntimeLimiter({
        environment,
        external:
          environment === "production" ? createPlatformLimiter() : undefined,
      }),
  }
}
