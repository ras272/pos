import "server-only"

import type { AuditSink, Authenticator, RateLimiter } from "@workspace/api"

import {
  createIdentityAuthenticator,
  createClaimsReader,
} from "../auth/identity"
import { createServerSupabaseClient } from "../supabase/server"

export type ActionSecurity = Readonly<{
  audit: AuditSink
  authenticate: Authenticator<void>
  createScopedClient: () => Promise<
    Awaited<ReturnType<typeof createServerSupabaseClient>> | undefined
  >
  environment: "development" | "production" | "test"
  rateLimit: RateLimiter
}>

function environment(): ActionSecurity["environment"] {
  if (process.env.NODE_ENV === "production") return "production"
  if (process.env.NODE_ENV === "test") return "test"
  return "development"
}

const audit: AuditSink = {
  async write(event) {
    process.stdout.write(
      `${JSON.stringify({
        action: event.action,
        actorId: event.actorId,
        code: event.code,
        decision: event.decision,
        requestId: event.requestId,
        resourceId: event.resourceId,
        source: "admin",
        type: "audit",
      })}\n`
    )
  },
}

/**
 * Una Server Action es un POST expuesto a la red. Esta fÃ¡brica arma las mismas
 * dependencias que exige una route: identidad verificada, cliente con alcance
 * de usuario, limitador y auditorÃ­a. No define wrappers propios para que el
 * checker de entrypoints siga viendo la llamada directa a
 * `defineAuthenticatedAction`.
 */
export function actionSecurity(
  overrides: Partial<ActionSecurity> = {}
): ActionSecurity {
  const resolved = overrides.environment ?? environment()

  return {
    audit: overrides.audit ?? audit,

    authenticate:
      overrides.authenticate ??
      createIdentityAuthenticator(async () => {
        const client = await createServerSupabaseClient()
        return createClaimsReader(client)()
      }),

    createScopedClient:
      overrides.createScopedClient ??
      (async () => createServerSupabaseClient()),

    environment: resolved,

    // TodavÃ­a no hay backend de lÃ­mites compartido. En producciÃ³n esto falla
    // cerrado antes de servir la primera Server Action; es un bloqueante de
    // `docs/PRODUCTION_READINESS.md`.
    rateLimit: overrides.rateLimit ?? {
      kind: resolved === "production" ? "external" : "development-memory",
      async limit() {
        if (resolved === "production") {
          throw new Error("No external rate-limit backend is configured")
        }
        return { allowed: true }
      },
    },
  }
}
