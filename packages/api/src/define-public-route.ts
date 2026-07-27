import type { z } from "zod"

import type { AuditSink } from "./audit.js"
import { errorResponse } from "./errors.js"
import { auditAllowed, createResponseFailure } from "./fail-closed.js"
import { createRequestId, readJson, successResponse } from "./json.js"
import {
  assertNamedRateLimitPolicy,
  assertProductionRateLimiter,
  isExecutableRateLimiter,
  type RateLimiter,
} from "./rate-limit.js"

type PublicEntryPoint = { method: string; path: string }

type PublicRouteContext<Input> = { input: Input; request: Request }

function assertPublicEntryPoint(entryPoint: PublicEntryPoint): void {
  if (!entryPoint.method.trim() || !entryPoint.path.startsWith("/")) {
    throw new Error(
      "A public entry point requires a method and an absolute path"
    )
  }
}

function matchesEntryPoint(
  request: Request,
  entryPoint: PublicEntryPoint
): boolean {
  if (request.method.toUpperCase() !== entryPoint.method.toUpperCase()) {
    return false
  }
  try {
    return new URL(request.url).pathname === entryPoint.path
  } catch {
    return false
  }
}

type PublicRouteOptions<Input, Output, Dto> = {
  action: string
  environment?: "development" | "production" | "test"
  schema: z.ZodType<Input>
  publicEntryPoint: PublicEntryPoint
  isPublicEntryPointApproved: (entryPoint: PublicEntryPoint) => Promise<boolean>
  rateLimit: RateLimiter
  rateLimitPolicy: string
  audit: AuditSink
  resourceId?: (input: Input) => string | undefined
  toDto: (output: Output) => Dto
  handler: (context: PublicRouteContext<Input>) => Promise<Output>
}

export function definePublicRoute<Input, Output, Dto>(
  options: PublicRouteOptions<Input, Output, Dto>
) {
  assertNamedRateLimitPolicy(options.rateLimitPolicy)
  assertProductionRateLimiter(options.environment, options.rateLimit)
  assertPublicEntryPoint(options.publicEntryPoint)

  return async (request: Request): Promise<Response> => {
    const requestId = createRequestId()
    const context = {
      action: options.action,
      audit: options.audit,
      requestId,
    }
    const fail = createResponseFailure(context)

    // La aprobación del manifiesto vale para un método y una ruta concretos: si
    // la request no es esa, la ruta está montada fuera de lo revisado.
    if (!matchesEntryPoint(request, options.publicEntryPoint)) {
      return fail({
        code: "public_entrypoint_mismatch",
        decision: "deny",
        status: 503,
      })
    }

    let approved: boolean
    try {
      approved = await options.isPublicEntryPointApproved(
        options.publicEntryPoint
      )
    } catch {
      return fail({
        code: "public_entrypoint_unavailable",
        decision: "error",
        status: 503,
      })
    }
    if (!approved) {
      return fail({
        code: "public_entrypoint_unavailable",
        decision: "deny",
        status: 503,
      })
    }

    const body = await readJson(request)
    if (!body.ok) return errorResponse(400, "invalid_json", requestId)

    const input = options.schema.safeParse(body.value)
    if (!input.success) return errorResponse(422, "invalid_input", requestId)

    if (!isExecutableRateLimiter(options.rateLimit)) {
      return fail({
        code: "rate_limiter_unavailable",
        decision: "error",
        status: 503,
      })
    }

    let resourceId: string | null = null
    try {
      resourceId = options.resourceId?.(input.data) ?? null
    } catch {
      return fail({
        code: "resource_unavailable",
        decision: "error",
        status: 503,
      })
    }

    let rateLimit: Awaited<ReturnType<RateLimiter["limit"]>>
    try {
      rateLimit = await options.rateLimit.limit({
        action: options.action,
        actorId: null,
        policy: options.rateLimitPolicy,
        resourceId,
      })
    } catch {
      return fail({
        code: "rate_limiter_unavailable",
        decision: "error",
        resourceId,
        status: 503,
      })
    }
    if (!rateLimit.allowed) {
      return fail({
        code: "rate_limited",
        decision: "rate_limited",
        headers: { "Retry-After": String(rateLimit.retryAfterSeconds ?? 60) },
        resourceId,
        status: 429,
      })
    }

    if (!(await auditAllowed(context, { resourceId }))) {
      return errorResponse(503, "audit_unavailable", requestId)
    }

    try {
      const output = await options.handler({ input: input.data, request })
      return successResponse(options.toDto(output), requestId)
    } catch {
      return fail({
        code: "internal_error",
        decision: "error",
        resourceId,
        status: 500,
      })
    }
  }
}
