import { describe, expect, it } from "vitest"
import { z } from "zod"

import { defineAuthenticatedAction } from "./index.js"

describe("defineAuthenticatedAction", () => {
  it("returns a safe 401 result when verified identity is absent", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => undefined,
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "unauthenticated" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        actorId: null,
        code: "unauthenticated",
        decision: "deny",
      }),
    ])
  })

  it("returns a safe 422 result for invalid action input", async () => {
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string().uuid() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "invalid" })).resolves.toMatchObject({
      error: { code: "invalid_input" },
      ok: false,
    })
  })

  it("returns a safe 403 result when action authorization denies the actor", async () => {
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: false }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "unauthorized" },
      ok: false,
    })
  })

  it("validates, authorizes, scopes, limits, audits, and returns a DTO", async () => {
    const calls: string[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => {
        calls.push("authenticate")
        return { id: "actor-1" }
      },
      authorize: async () => {
        calls.push("authorize")
        return { allowed: true }
      },
      createScopedClient: async () => {
        calls.push("scoped-client")
        return { actorId: "actor-1" }
      },
      rateLimit: {
        kind: "external",
        limit: async () => {
          calls.push("rate-limit")
          return { allowed: true }
        },
      },
      rateLimitPolicy: "orders.create",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          calls.push(`${event.decision}:${event.code}`)
        },
      },
      toDto: (value: { id: string; internal: string }) => ({ id: value.id }),
      handler: async ({ actor, client, input }) => {
        calls.push("handler")
        return {
          id: `${actor.id}:${client.actorId}:${input.orderId}`,
          internal: "row-data",
        }
      },
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      data: { id: "actor-1:actor-1:order-1" },
      ok: true,
    })
    expect(calls).toEqual([
      "authenticate",
      "authorize",
      "scoped-client",
      "rate-limit",
      "allow:ok",
      "handler",
    ])
  })

  it("rejects the development in-memory limiter in production", () => {
    expect(() =>
      defineAuthenticatedAction({
        action: "orders.create",
        environment: "production",
        schema: z.object({ orderId: z.string() }),
        authenticate: async () => ({ id: "actor-1" }),
        authorize: async () => ({ allowed: true }),
        createScopedClient: async () => ({}),
        rateLimit: {
          kind: "development-memory",
          limit: async () => ({ allowed: true }),
        },
        rateLimitPolicy: "orders.create",
        audit: { write: async () => undefined },
        toDto: (value: { id: string }) => value,
        handler: async () => ({ id: "order-1" }),
      })
    ).toThrow(/in-memory limiter/i)
  })

  it("audits an authorization denial", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: false }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "unauthorized" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        action: "orders.create",
        actorId: "actor-1",
        code: "unauthorized",
        decision: "deny",
        resourceId: "order-1",
      }),
    ])
  })

  it("returns a safe audited result when authentication throws", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => Promise.reject(new Error("token=hidden")),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "authentication_unavailable" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        actorId: null,
        code: "authentication_unavailable",
        decision: "error",
      }),
    ])
  })

  it("audits a safe error when the action handler throws", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        throw new Error("cookie=never-log")
      },
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "internal_error" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({ decision: "allow", code: "ok" }),
      expect.objectContaining({ decision: "error", code: "internal_error" }),
    ])
    expect(JSON.stringify(events)).not.toContain("never-log")
  })

  it("audits an action rate-limit denial", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async () => ({ allowed: false, retryAfterSeconds: 30 }),
      },
      rateLimitPolicy: "orders.create",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "rate_limited" },
      ok: false,
      retryAfterSeconds: 30,
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limited",
        decision: "rate_limited",
      }),
    ])
  })

  it("returns a safe audited result when action authorization throws", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => Promise.reject(new Error("SQL=hidden")),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "authorization_unavailable" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "authorization_unavailable",
        decision: "error",
      }),
    ])
  })

  it("returns a safe audited result when action scoped-client creation throws", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => Promise.reject(new Error("jwt=hidden")),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.create",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "scoped_client_unavailable" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "scoped_client_unavailable",
        decision: "error",
      }),
    ])
  })

  it("returns a safe audited result when action rate limiting throws", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async () => Promise.reject(new Error("token=hidden")),
      },
      rateLimitPolicy: "orders.create",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "rate_limiter_unavailable" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })

  it("audits a non-executable action limiter before failing closed", async () => {
    const events: unknown[] = []
    const action = defineAuthenticatedAction({
      action: "orders.create",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external" } as never,
      rateLimitPolicy: "orders.create",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await expect(action({ orderId: "order-1" })).resolves.toMatchObject({
      error: { code: "rate_limiter_unavailable" },
      ok: false,
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })
})
