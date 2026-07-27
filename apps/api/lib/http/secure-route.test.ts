import { defineAuthenticatedRoute } from "@workspace/api"
import { describe, expect, it, vi } from "vitest"
import { z } from "zod"

import { routeSecurity, securityEnvironment } from "./secure-route"

const schema = z.object({ subject: z.string().min(1) }).strict()

function post(body: unknown, authorization = "Bearer token") {
  return new Request("https://api.example.com/api/security-contract", {
    body: JSON.stringify(body),
    headers: { authorization, "content-type": "application/json" },
    method: "POST",
  })
}

describe("securityEnvironment", () => {
  it("only reports production when NODE_ENV says so", () => {
    vi.stubEnv("NODE_ENV", "production")
    expect(securityEnvironment()).toBe("production")
    vi.stubEnv("NODE_ENV", "test")
    expect(securityEnvironment()).toBe("test")
    vi.stubEnv("NODE_ENV", "development")
    expect(securityEnvironment()).toBe("development")
    vi.unstubAllEnvs()
  })
})

describe("routeSecurity", () => {
  it("uses the in-memory limiter outside production", () => {
    expect(routeSecurity({ environment: "test" }).rateLimit.kind).toBe(
      "development-memory"
    )
  })

  it("uses a limiter that fails closed in production", async () => {
    const { rateLimit } = routeSecurity({ environment: "production" })

    expect(rateLimit.kind).toBe("external")
    await expect(
      rateLimit.limit({
        action: "security.contract",
        actorId: "actor-1",
        policy: "security.contract",
        resourceId: null,
      })
    ).rejects.toThrowError(/No external rate-limit backend is configured/)
  })

  it("refuses to build a scoped client without a verified credential", async () => {
    const { createScopedClient } = routeSecurity({ environment: "test" })

    await expect(createScopedClient({})).resolves.toBeUndefined()
  })

  it("composes into a wrapper that never runs the handler unauthenticated", async () => {
    const handler = vi.fn()
    const route = defineAuthenticatedRoute({
      ...routeSecurity({
        audit: { write: async () => undefined },
        authenticate: async () => undefined,
        environment: "test",
      }),
      action: "security.contract",
      authorize: async () => ({ allowed: true }),
      handler,
      rateLimitPolicy: "security.contract",
      schema,
      toDto: (output: { subject: string }) => output,
    })

    const response = await route(post({ subject: "actor-1" }))

    expect(response.status).toBe(401)
    expect(handler).not.toHaveBeenCalled()
  })

  it("composes into a wrapper that never runs the handler unauthorized", async () => {
    const handler = vi.fn()
    const route = defineAuthenticatedRoute({
      ...routeSecurity({
        audit: { write: async () => undefined },
        authenticate: async () => ({ credential: "token", id: "actor-1" }),
        createScopedClient: async () => ({}) as never,
        environment: "test",
      }),
      action: "security.contract",
      authorize: async () => ({ allowed: false }),
      handler,
      rateLimitPolicy: "security.contract",
      schema,
      toDto: (output: { subject: string }) => output,
    })

    const response = await route(post({ subject: "otro-actor" }))

    expect(response.status).toBe(403)
    expect(handler).not.toHaveBeenCalled()
  })

  it("composes into a wrapper that never runs the handler without a scoped client", async () => {
    const handler = vi.fn()
    const route = defineAuthenticatedRoute({
      ...routeSecurity({
        audit: { write: async () => undefined },
        authenticate: async () => ({ id: "actor-1" }),
        environment: "test",
      }),
      action: "security.contract",
      authorize: async () => ({ allowed: true }),
      handler,
      rateLimitPolicy: "security.contract",
      schema,
      toDto: (output: { subject: string }) => output,
    })

    const response = await route(post({ subject: "actor-1" }))

    expect(response.status).toBe(503)
    expect(handler).not.toHaveBeenCalled()
  })

  it("composes into a wrapper that never runs the handler on invalid input", async () => {
    const handler = vi.fn()
    const route = defineAuthenticatedRoute({
      ...routeSecurity({
        audit: { write: async () => undefined },
        authenticate: async () => ({ credential: "token", id: "actor-1" }),
        createScopedClient: async () => ({}) as never,
        environment: "test",
      }),
      action: "security.contract",
      authorize: async () => ({ allowed: true }),
      handler,
      rateLimitPolicy: "security.contract",
      schema,
      toDto: (output: { subject: string }) => output,
    })

    const invalid = await route(post({ subject: "" }))
    expect(invalid.status).toBe(422)

    const malformed = await route(
      new Request("https://api.example.com/api/security-contract", {
        body: "no-json",
        headers: {
          authorization: "Bearer t",
          "content-type": "application/json",
        },
        method: "POST",
      })
    )
    expect(malformed.status).toBe(400)
    expect(handler).not.toHaveBeenCalled()
  })

  it("runs the handler and returns a DTO once every control passes", async () => {
    const route = defineAuthenticatedRoute({
      ...routeSecurity({
        audit: { write: async () => undefined },
        authenticate: async () => ({ credential: "token", id: "actor-1" }),
        createScopedClient: async () => ({}) as never,
        environment: "test",
      }),
      action: "security.contract",
      authorize: async (input, actor) => ({
        allowed: input.subject === actor.id,
      }),
      handler: async ({ actor }) => ({ subject: actor.id }),
      rateLimitPolicy: "security.contract",
      schema,
      toDto: (output: { subject: string }) => ({
        contract: "authenticated" as const,
        subject: output.subject,
      }),
    })

    const response = await route(post({ subject: "actor-1" }))

    expect(response.status).toBe(200)
    expect(response.headers.get("Cache-Control")).toBe("private, no-store")
    const body = await response.json()
    expect(body.data).toEqual({ contract: "authenticated", subject: "actor-1" })
    // La credencial verificada nunca sale en la respuesta.
    expect(JSON.stringify(body)).not.toContain("token")
  })
})
