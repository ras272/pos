import { describe, expect, it, vi } from "vitest"

import { createClaimsReader, createIdentityAuthenticator } from "./identity"

function client(result: unknown, getSession = vi.fn()) {
  return {
    auth: {
      getClaims: vi.fn(async () => result as never),
      getSession,
    },
  }
}

describe("createClaimsReader", () => {
  it("never falls back to getSession for authorization", async () => {
    const getSession = vi.fn()
    const supabase = client(
      { data: { claims: { sub: "actor-1" } }, error: null },
      getSession
    )

    await createClaimsReader(supabase)()

    expect(supabase.auth.getClaims).toHaveBeenCalledTimes(1)
    expect(getSession).not.toHaveBeenCalled()
  })

  it("discards claims when the token is invalid or expired", async () => {
    const supabase = client({ data: null, error: new Error("jwt expired") })

    await expect(createClaimsReader(supabase)()).resolves.toBeUndefined()
  })

  it("discards an empty payload", async () => {
    await expect(
      createClaimsReader(client({ data: {}, error: null }))()
    ).resolves.toBeUndefined()
  })
})

describe("createIdentityAuthenticator", () => {
  it("accepts only a verified string sub", async () => {
    const authenticate = createIdentityAuthenticator(async () => ({
      sub: "8f1c2c66-1a1e-4a53-9f1e-9c0b3b1a2d44",
    }))

    await expect(authenticate()).resolves.toEqual({
      id: "8f1c2c66-1a1e-4a53-9f1e-9c0b3b1a2d44",
    })
  })

  it("rejects a missing, empty or non-string sub", async () => {
    await expect(
      createIdentityAuthenticator(async () => undefined)()
    ).resolves.toBeUndefined()
    await expect(
      createIdentityAuthenticator(async () => ({}))()
    ).resolves.toBeUndefined()
    await expect(
      createIdentityAuthenticator(async () => ({ sub: "" }))()
    ).resolves.toBeUndefined()
    await expect(
      createIdentityAuthenticator(async () => ({ sub: 7 }))()
    ).resolves.toBeUndefined()
  })

  it("ignores tenant and role claims carried by the token", async () => {
    const authenticate = createIdentityAuthenticator(async () => ({
      app_metadata: { role: "owner", tenant_id: "tenant-ajeno" },
      sub: "actor-1",
      user_metadata: { role: "owner" },
    }))

    await expect(authenticate()).resolves.toEqual({ id: "actor-1" })
  })
})
