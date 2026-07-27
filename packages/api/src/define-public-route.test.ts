import { describe, expect, it } from "vitest"
import { z } from "zod"

import { definePublicRoute } from "./index.js"

describe("definePublicRoute", () => {
  it("fails closed when the public-entrypoint manifest does not approve the exemption", async () => {
    let handlerCalled = false
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => false,
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => {
        handlerCalled = true
        return { accepted: true }
      },
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
    expect(events).toEqual([
      expect.objectContaining({
        code: "public_entrypoint_unavailable",
        decision: "deny",
      }),
    ])
  })

  it("validates, limits, audits, and returns only a DTO for an approved exemption", async () => {
    const calls: string[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => {
        calls.push("manifest")
        return true
      },
      rateLimit: {
        kind: "external",
        limit: async () => {
          calls.push("rate-limit")
          return { allowed: true }
        },
      },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          calls.push(`${event.decision}:${event.code}`)
        },
      },
      toDto: (value: { accepted: boolean; internal: string }) => ({
        accepted: value.accepted,
      }),
      handler: async ({ input }) => {
        calls.push(`handler:${input.event}`)
        return { accepted: true, internal: "raw-row-data" }
      },
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )
    const body = await response.text()

    expect(response.status).toBe(200)
    expect(body).toContain("accepted")
    expect(body).not.toContain("raw-row-data")
    expect(calls).toEqual([
      "manifest",
      "rate-limit",
      "allow:ok",
      "handler:created",
    ])
  })

  it("rejects the development in-memory limiter in production", () => {
    expect(() =>
      definePublicRoute({
        action: "webhooks.receive",
        environment: "production",
        schema: z.object({ event: z.string() }),
        publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
        isPublicEntryPointApproved: async () => true,
        rateLimit: {
          kind: "development-memory",
          limit: async () => ({ allowed: true }),
        },
        rateLimitPolicy: "webhooks.receive",
        audit: { write: async () => undefined },
        toDto: (value: { accepted: boolean }) => value,
        handler: async () => ({ accepted: true }),
      })
    ).toThrow(/in-memory limiter/i)
  })

  it("returns a safe error when manifest approval lookup fails", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () =>
        Promise.reject(new Error("manifest token=hidden")),
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => ({ accepted: true }),
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        code: "public_entrypoint_unavailable",
        decision: "error",
      }),
    ])
  })

  it("audits a rate-limit denial before returning 429", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: {
        kind: "external",
        limit: async () => ({ allowed: false, retryAfterSeconds: 30 }),
      },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => ({ accepted: true }),
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(429)
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limited",
        decision: "rate_limited",
      }),
    ])
  })

  it("audits a safe error outcome when the public handler throws", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => {
        throw new Error("payload=never-log")
      },
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(500)
    expect(events).toEqual([
      expect.objectContaining({ code: "ok", decision: "allow" }),
      expect.objectContaining({ code: "internal_error", decision: "error" }),
    ])
    expect(JSON.stringify(events)).not.toContain("never-log")
  })

  it("returns a safe audited response when public rate limiting throws", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: {
        kind: "external",
        limit: async () => Promise.reject(new Error("token=hidden")),
      },
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => ({ accepted: true }),
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })

  it("returns a safe audited response when public resource extraction throws", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "webhooks.receive",
      resourceId: () => {
        throw new Error("payload=hidden")
      },
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => ({ accepted: true }),
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    await expect(response.text()).resolves.not.toContain("hidden")
    expect(events).toEqual([
      expect.objectContaining({
        code: "resource_unavailable",
        decision: "error",
      }),
    ])
  })

  it("audits a non-executable public limiter before failing closed", async () => {
    const events: unknown[] = []
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: { kind: "external" } as never,
      rateLimitPolicy: "webhooks.receive",
      audit: {
        write: async (event) => {
          events.push(event)
        },
      },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => ({ accepted: true }),
    })

    const response = await route(
      new Request("https://example.test/webhooks/provider", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(events).toEqual([
      expect.objectContaining({
        code: "rate_limiter_unavailable",
        decision: "error",
      }),
    ])
  })

  it("rejects a request whose method or path differs from its approved manifest entry", async () => {
    let handlerCalled = false
    const route = definePublicRoute({
      action: "webhooks.receive",
      schema: z.object({ event: z.string() }),
      publicEntryPoint: { method: "POST", path: "/webhooks/provider" },
      isPublicEntryPointApproved: async () => true,
      rateLimit: { kind: "external", limit: async () => ({ allowed: true }) },
      rateLimitPolicy: "webhooks.receive",
      audit: { write: async () => undefined },
      toDto: (value: { accepted: boolean }) => value,
      handler: async () => {
        handlerCalled = true
        return { accepted: true }
      },
    })

    const response = await route(
      new Request("https://example.test/webhooks/wrong", {
        body: JSON.stringify({ event: "created" }),
        headers: { "content-type": "application/json" },
        method: "POST",
      })
    )

    expect(response.status).toBe(503)
    expect(handlerCalled).toBe(false)
  })
})
