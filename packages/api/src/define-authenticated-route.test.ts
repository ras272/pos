import { describe, expect, it } from "vitest"
import { z } from "zod"

import { defineAuthenticatedRoute } from "./index"

describe("defineAuthenticatedRoute", () => {
  it("returns 401 when identity verification finds no actor", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => undefined,
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(401)
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "unauthenticated" },
    })
  })

  it("returns 403 when authorization denies the verified actor", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: false }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(403)
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "unauthorized" },
    })
  })

  it("returns 400 for malformed JSON without executing authorization", async () => {
    let authorizationCalled = false
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => {
        authorizationCalled = true
        return { allowed: true }
      },
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(400)
    expect(authorizationCalled).toBe(false)
  })

  it("returns 422 when JSON does not satisfy the Zod schema", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string().uuid() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "not-a-uuid" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(422)
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "invalid_input" },
    })
  })

  it("fails closed when a user-scoped client is unavailable", async () => {
    let handlerCalled = false
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => undefined,
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        handlerCalled = true
        return { id: "order-1" }
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
  })

  it("fails closed when the rate limiter is not executable", async () => {
    let handlerCalled = false
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external" } as never,
      rateLimitPolicy: "orders.read",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        handlerCalled = true
        return { id: "order-1" }
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })

  it("returns 429 and Retry-After when the named limiter denies", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async () => ({ allowed: false, retryAfterSeconds: 30 }),
      },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(429)
    expect(response.headers.get("retry-after")).toBe("30")
  })

  it("fails closed when no async audit sink is configured", async () => {
    let handlerCalled = false
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: undefined as never,
      toDto: (value: { id: string }) => value,
      handler: async () => {
        handlerCalled = true
        return { id: "order-1" }
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
  })

  it("fails closed when the pre-handler audit write fails", async () => {
    let handlerCalled = false
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => Promise.reject(new Error("audit offline")) },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        handlerCalled = true
        return { id: "order-1" }
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
  })

  it("redacts unexpected handler errors behind a safe 500 response", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        throw new Error("internal token=do-not-disclose")
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )
    const body = await response.text()

    expect(response.status).toBe(500)
    expect(body).toContain("internal_error")
    expect(body).not.toContain("do-not-disclose")
  })

  it("returns only the DTO mapped from the handler result", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string; internal: string }) => ({ id: value.id }),
      handler: async () => ({ id: "order-1", internal: "raw-row-value" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )
    const body = await response.text()

    expect(response.status).toBe(200)
    expect(body).toContain("order-1")
    expect(body).not.toContain("raw-row-value")
  })

  it("executes the controls on every invocation and supplies typed context", async () => {
    const calls: string[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
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
      rateLimitPolicy: "orders.read",
      audit: {
        write: async () => {
          calls.push("audit")
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async ({ actor, client, input }) => {
        calls.push("handler")
        return { id: `${actor.id}:${client.actorId}:${input.orderId}` }
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(200)
    await expect(response.json()).resolves.toEqual({
      data: { id: "actor-1:actor-1:order-1" },
    })
    expect(calls).toEqual([
      "authenticate",
      "authorize",
      "scoped-client",
      "rate-limit",
      "audit",
      "handler",
    ])
  })

  it("adds no-store JSON headers and a request ID to successful responses", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.headers.get("cache-control")).toBe("private, no-store")
    expect(response.headers.get("content-type")).toContain("application/json")
    expect(response.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/)
  })

  it("adds no-store JSON headers and a request ID to safe error responses", async () => {
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => undefined,
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(new Request("https://example.test/orders"))
    const body = await response.json()

    expect(response.headers.get("cache-control")).toBe("private, no-store")
    expect(response.headers.get("content-type")).toContain("application/json")
    expect(response.headers.get("x-request-id")).toBe(body.requestId)
  })

  it("rejects the development in-memory limiter during production construction", () => {
    expect(() =>
      defineAuthenticatedRoute({
        action: "orders.read",
        environment: "production",
        schema: z.object({}),
        authenticate: async () => ({ id: "actor-1" }),
        authorize: async () => ({ allowed: true }),
        createScopedClient: async () => ({}),
        rateLimit: {
          kind: "development-memory",
          limit: async () => ({ allowed: true }),
        },
        rateLimitPolicy: "orders.read",
        audit: { write: async () => undefined },
        toDto: (value: { id: string }) => value,
        handler: async () => ({ id: "order-1" }),
      })
    ).toThrow(/in-memory limiter/i)
  })

  it("requires an explicit development or test environment for the in-memory limiter", () => {
    expect(() =>
      defineAuthenticatedRoute({
        action: "orders.read",
        schema: z.object({}),
        authenticate: async () => ({ id: "actor-1" }),
        authorize: async () => ({ allowed: true }),
        createScopedClient: async () => ({}),
        rateLimit: {
          kind: "development-memory",
          limit: async () => ({ allowed: true }),
        },
        rateLimitPolicy: "orders.read",
        audit: { write: async () => undefined },
        toDto: (value: { id: string }) => value,
        handler: async () => ({ id: "order-1" }),
      })
    ).toThrow(/development.*test/i)
  })

  it("requires a non-empty named rate-limit policy", () => {
    expect(() =>
      defineAuthenticatedRoute({
        action: "orders.read",
        schema: z.object({}),
        authenticate: async () => ({ id: "actor-1" }),
        authorize: async () => ({ allowed: true }),
        createScopedClient: async () => ({}),
        rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
        rateLimitPolicy: " ",
        audit: { write: async () => undefined },
        toDto: (value: { id: string }) => value,
        handler: async () => ({ id: "order-1" }),
      })
    ).toThrow(/named rate-limit policy/i)
  })

  it("passes the named policy and verified actor to the executable limiter", async () => {
    let decisionInput: unknown
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async (input) => {
          decisionInput = input
          return { allowed: true }
        },
      },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: { write: async () => undefined },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(decisionInput).toEqual({
      action: "orders.read",
      actorId: "actor-1",
      policy: "orders.read",
      resourceId: "order-1",
    })
  })

  it("emits a redacted structured allow audit event", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(events).toEqual([
      expect.objectContaining({
        action: "orders.read",
        actorId: "actor-1",
        code: "ok",
        decision: "allow",
        resourceId: "order-1",
      }),
    ])
    expect(events[0]).toHaveProperty("requestId")
    expect(JSON.stringify(events[0])).not.toMatch(
      /authorization|cookie|payload|token/i
    )
  })

  it("audits an authorization denial before returning 403", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: false }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(403)
    expect(events).toEqual([
      expect.objectContaining({
        action: "orders.read",
        actorId: "actor-1",
        code: "unauthorized",
        decision: "deny",
        resourceId: "order-1",
      }),
    ])
  })

  it("audits an unauthenticated denial without trusting an actor from the request", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => undefined,
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(new Request("https://example.test/orders"))

    expect(response.status).toBe(401)
    expect(events).toEqual([
      expect.objectContaining({
        action: "orders.read",
        actorId: null,
        code: "unauthenticated",
        decision: "deny",
        resourceId: null,
      }),
    ])
  })

  it("audits rate-limit denials before returning 429", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async () => ({ allowed: false, retryAfterSeconds: 30 }),
      },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(429)
    expect(events).toEqual([
      expect.objectContaining({
        action: "orders.read",
        actorId: "actor-1",
        code: "rate_limited",
        decision: "rate_limited",
        resourceId: "order-1",
      }),
    ])
  })

  it("audits a safe error outcome when the handler throws", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => {
        throw new Error("authorization token should never be audited")
      },
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(500)
    expect(events).toEqual([
      expect.objectContaining({ decision: "allow", code: "ok" }),
      expect.objectContaining({ decision: "error", code: "internal_error" }),
    ])
    expect(JSON.stringify(events)).not.toContain("never be audited")
  })

  it("fails closed with a safe audited result when the limiter throws", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: {
        kind: "external",
        limit: async () => Promise.reject(new Error("limiter secret=hidden")),
      },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "rate_limiter_unavailable" },
    })
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })

  it("fails closed with a safe audited response when authentication throws", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () =>
        Promise.reject(new Error("authorization=hidden")),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(new Request("https://example.test/orders"))

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        actorId: null,
        code: "authentication_unavailable",
        decision: "error",
      }),
    ])
  })

  it("fails closed with a safe audited response when authorization throws", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({ orderId: z.string() }),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => Promise.reject(new Error("SQL details=hidden")),
      createScopedClient: async () => ({}),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      resourceId: (input) => input.orderId,
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: JSON.stringify({ orderId: "order-1" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        code: "authorization_unavailable",
        decision: "error",
      }),
    ])
  })

  it("fails closed with a safe audited response when scoped-client creation throws", async () => {
    const events: unknown[] = []
    const route = defineAuthenticatedRoute({
      action: "orders.read",
      schema: z.object({}),
      authenticate: async () => ({ id: "actor-1" }),
      authorize: async () => ({ allowed: true }),
      createScopedClient: async () => Promise.reject(new Error("jwt=hidden")),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "orders.read",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { id: string }) => value,
      handler: async () => ({ id: "order-1" }),
    })

    const response = await route(
      new Request("https://example.test/orders", {
        body: "{}",
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        code: "scoped_client_unavailable",
        decision: "error",
      }),
    ])
  })
})
