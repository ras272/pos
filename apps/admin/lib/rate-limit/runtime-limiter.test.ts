import { describe, expect, it } from "vitest"

import {
  createInMemoryLimiter,
  createPlatformLimiter,
  createRuntimeLimiter,
} from "./runtime-limiter"

const input = {
  action: "tenant.update",
  actorId: "actor-1",
  policy: "tenant.update",
  resourceId: null,
}

describe("createInMemoryLimiter", () => {
  it("actually denies once the budget is spent", async () => {
    let clock = 0
    const limiter = createInMemoryLimiter({
      now: () => clock,
      requestsPerWindow: 2,
      windowMs: 1000,
    })

    await expect(limiter.limit(input)).resolves.toEqual({ allowed: true })
    await expect(limiter.limit(input)).resolves.toEqual({ allowed: true })

    const denied = await limiter.limit(input)
    expect(denied.allowed).toBe(false)
    expect(denied.retryAfterSeconds).toBe(1)

    clock = 1000
    await expect(limiter.limit(input)).resolves.toEqual({ allowed: true })
  })

  it("counts each actor separately", async () => {
    const limiter = createInMemoryLimiter({ requestsPerWindow: 1 })

    await expect(limiter.limit(input)).resolves.toEqual({ allowed: true })
    await expect(
      limiter.limit({ ...input, actorId: "actor-2" })
    ).resolves.toEqual({ allowed: true })
  })
})

describe("createRuntimeLimiter", () => {
  it("refuses to build a production limiter without an external one", () => {
    expect(() =>
      createRuntimeLimiter({ environment: "production" })
    ).toThrowError(/externally enforced rate limiter/)
  })

  it("refuses an in-memory limiter passed as the production one", () => {
    expect(() =>
      createRuntimeLimiter({
        environment: "production",
        external: createInMemoryLimiter(),
      })
    ).toThrowError(/kind 'external'/)
  })

  it("uses the in-memory limiter outside production", () => {
    expect(createRuntimeLimiter({ environment: "development" }).kind).toBe(
      "development-memory"
    )
  })
})

describe("createPlatformLimiter", () => {
  it("fails closed while no backend is configured", async () => {
    const limiter = createPlatformLimiter()

    expect(limiter.kind).toBe("external")
    await expect(limiter.limit(input)).rejects.toThrowError(
      /No external rate-limit backend is configured/
    )
  })
})
