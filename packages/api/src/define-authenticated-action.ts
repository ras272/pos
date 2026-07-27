import type { z } from "zod"

import type { AuditSink } from "./audit.js"
import type { Authenticator, VerifiedActor } from "./authenticate.js"
import type { Authorizer } from "./authorize.js"
import {
  actionFailure,
  auditAllowed,
  auditFailure,
  createActionFailure,
} from "./fail-closed.js"
import { createRequestId } from "./json.js"
import {
  assertNamedRateLimitPolicy,
  assertProductionRateLimiter,
  isExecutableRateLimiter,
  type RateLimiter,
} from "./rate-limit.js"

type AuthenticatedActionContext<Input, Client> = {
  actor: VerifiedActor
  client: Client
  input: Input
}

type AuthenticatedActionOptions<Input, Client, Output, Dto> = {
  action: string
  environment?: "development" | "production" | "test"
  schema: z.ZodType<Input>
  authenticate: Authenticator<void>
  authorize: Authorizer<Input>
  createScopedClient: (actor: VerifiedActor) => Promise<Client | undefined>
  rateLimit: RateLimiter
  rateLimitPolicy: string
  audit: AuditSink
  resourceId?: (input: Input) => string | undefined
  toDto: (output: Output) => Dto
  handler: (
    context: AuthenticatedActionContext<Input, Client>
  ) => Promise<Output>
}

export function defineAuthenticatedAction<Input, Client, Output, Dto>(
  options: AuthenticatedActionOptions<Input, Client, Output, Dto>
) {
  assertNamedRateLimitPolicy(options.rateLimitPolicy)
  assertProductionRateLimiter(options.environment, options.rateLimit)

  return async (value: unknown) => {
    const requestId = createRequestId()
    const context = {
      action: options.action,
      audit: options.audit,
      requestId,
    }
    const fail = createActionFailure(context)

    let actor: VerifiedActor | undefined
    try {
      actor = await options.authenticate()
    } catch {
      return fail({ code: "authentication_unavailable", decision: "error" })
    }
    if (!actor) return fail({ code: "unauthenticated", decision: "deny" })

    const input = options.schema.safeParse(value)
    if (!input.success) return actionFailure("invalid_input", requestId)

    let resourceId: string | null = null
    let authorization: Awaited<ReturnType<Authorizer<Input>>>
    try {
      resourceId = options.resourceId?.(input.data) ?? null
      authorization = await options.authorize(input.data, actor)
    } catch {
      return fail({
        actorId: actor.id,
        code: "authorization_unavailable",
        decision: "error",
        resourceId,
      })
    }
    if (!authorization.allowed) {
      return fail({
        actorId: actor.id,
        code: "unauthorized",
        decision: "deny",
        resourceId,
      })
    }

    const scopedClientUnavailable = {
      actorId: actor.id,
      code: "scoped_client_unavailable",
      decision: "error" as const,
      resourceId,
    }
    let client: Client | undefined
    try {
      client = await options.createScopedClient(actor)
    } catch {
      return fail(scopedClientUnavailable)
    }
    if (!client) return fail(scopedClientUnavailable)

    const limiterUnavailable = {
      actorId: actor.id,
      code: "rate_limiter_unavailable",
      decision: "error" as const,
      resourceId,
    }
    if (!isExecutableRateLimiter(options.rateLimit)) {
      return fail(limiterUnavailable)
    }

    let rateLimit: Awaited<ReturnType<RateLimiter["limit"]>>
    try {
      rateLimit = await options.rateLimit.limit({
        action: options.action,
        actorId: actor.id,
        policy: options.rateLimitPolicy,
        resourceId,
      })
    } catch {
      return fail(limiterUnavailable)
    }
    if (!rateLimit.allowed) {
      const denied = {
        actorId: actor.id,
        code: "rate_limited",
        decision: "rate_limited" as const,
        resourceId,
      }
      if (!(await auditFailure(context, denied))) {
        return actionFailure("audit_unavailable", requestId)
      }
      return {
        ...actionFailure("rate_limited", requestId),
        retryAfterSeconds: rateLimit.retryAfterSeconds ?? 60,
      }
    }

    if (!(await auditAllowed(context, { actorId: actor.id, resourceId }))) {
      return actionFailure("audit_unavailable", requestId)
    }

    try {
      const output = await options.handler({ actor, client, input: input.data })
      return { data: options.toDto(output), ok: true as const, requestId }
    } catch {
      return fail({
        actorId: actor.id,
        code: "internal_error",
        decision: "error",
        resourceId,
      })
    }
  }
}
