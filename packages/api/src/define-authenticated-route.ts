import type { z } from "zod"

import type { AuditSink } from "./audit.js"
import type { Authenticator, VerifiedActor } from "./authenticate.js"
import type { Authorizer } from "./authorize.js"
import { errorResponse } from "./errors.js"
import { auditAllowed, createResponseFailure } from "./fail-closed.js"
import { createRequestId, readJson, successResponse } from "./json.js"
import {
  assertNamedRateLimitPolicy,
  assertProductionRateLimiter,
  isExecutableRateLimiter,
  type RateLimiter,
} from "./rate-limit.js"

type AuthenticatedRouteContext<Input, Client> = {
  actor: VerifiedActor
  client: Client
  input: Input
  request: Request
}

type AuthenticatedRouteOptions<Input, Client, Output, Dto> = {
  action: string
  environment?: "development" | "production" | "test"
  schema: z.ZodType<Input>
  authenticate: Authenticator<Request>
  authorize: Authorizer<Input>
  createScopedClient: (actor: VerifiedActor) => Promise<Client | undefined>
  rateLimit: RateLimiter
  rateLimitPolicy: string
  audit: AuditSink
  resourceId?: (input: Input) => string | undefined
  toDto: (output: Output) => Dto
  handler: (
    context: AuthenticatedRouteContext<Input, Client>
  ) => Promise<Output>
}

export function defineAuthenticatedRoute<Input, Client, Output, Dto>(
  options: AuthenticatedRouteOptions<Input, Client, Output, Dto>
) {
  assertNamedRateLimitPolicy(options.rateLimitPolicy)
  assertProductionRateLimiter(options.environment, options.rateLimit)

  return async (request: Request): Promise<Response> => {
    const requestId = createRequestId()
    const context = {
      action: options.action,
      audit: options.audit,
      requestId,
    }
    const fail = createResponseFailure(context)

    let actor: VerifiedActor | undefined
    try {
      actor = await options.authenticate(request)
    } catch {
      return fail({
        code: "authentication_unavailable",
        decision: "error",
        status: 503,
      })
    }
    if (!actor) {
      return fail({ code: "unauthenticated", decision: "deny", status: 401 })
    }

    const body = await readJson(request)
    if (!body.ok) return errorResponse(400, "invalid_json", requestId)

    const input = options.schema.safeParse(body.value)
    if (!input.success) return errorResponse(422, "invalid_input", requestId)

    let resourceId: string | undefined
    let authorization: Awaited<ReturnType<Authorizer<Input>>>
    try {
      resourceId = options.resourceId?.(input.data)
      authorization = await options.authorize(input.data, actor)
    } catch {
      return fail({
        actorId: actor.id,
        code: "authorization_unavailable",
        decision: "error",
        resourceId: resourceId ?? null,
        status: 503,
      })
    }
    if (!authorization.allowed) {
      return fail({
        actorId: actor.id,
        code: "unauthorized",
        decision: "deny",
        resourceId: resourceId ?? null,
        status: 403,
      })
    }

    const scopedClientUnavailable = {
      actorId: actor.id,
      code: "scoped_client_unavailable",
      decision: "error" as const,
      resourceId: resourceId ?? null,
      status: 503,
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
      resourceId: resourceId ?? null,
      status: 503,
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
        resourceId: resourceId ?? null,
      })
    } catch {
      return fail(limiterUnavailable)
    }
    if (!rateLimit.allowed) {
      return fail({
        actorId: actor.id,
        code: "rate_limited",
        decision: "rate_limited",
        headers: { "Retry-After": String(rateLimit.retryAfterSeconds ?? 60) },
        resourceId: resourceId ?? null,
        status: 429,
      })
    }

    if (
      !(await auditAllowed(context, {
        actorId: actor.id,
        resourceId: resourceId ?? null,
      }))
    ) {
      return errorResponse(503, "audit_unavailable", requestId)
    }

    try {
      const output = await options.handler({
        actor,
        client,
        input: input.data,
        request,
      })
      return successResponse(options.toDto(output), requestId)
    } catch {
      return fail({
        actorId: actor.id,
        code: "internal_error",
        decision: "error",
        resourceId: resourceId ?? null,
        status: 500,
      })
    }
  }
}
