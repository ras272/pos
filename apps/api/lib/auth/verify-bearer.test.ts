import { describe, expect, it, vi } from "vitest"

import { createBearerAuthenticator, readBearerToken } from "./verify-bearer"

function request(authorization?: string) {
  return new Request("https://api.example.com/api/security-contract", {
    headers: authorization ? { authorization } : undefined,
    method: "POST",
  })
}

describe("readBearerToken", () => {
  it("reads the token regardless of scheme casing", () => {
    expect(readBearerToken(request("Bearer abc.def.ghi"))).toBe("abc.def.ghi")
    expect(readBearerToken(request("bearer abc.def.ghi"))).toBe("abc.def.ghi")
  })

  it("ignores a missing or foreign scheme", () => {
    expect(readBearerToken(request())).toBeUndefined()
    expect(readBearerToken(request("Basic abc"))).toBeUndefined()
    expect(readBearerToken(request("Bearer"))).toBeUndefined()
    expect(readBearerToken(request("Bearer "))).toBeUndefined()
  })
})

describe("createBearerAuthenticator", () => {
  it("does not call the verifier when there is no bearer token", async () => {
    const verify = vi.fn()
    const authenticate = createBearerAuthenticator(verify)

    await expect(authenticate(request())).resolves.toBeUndefined()
    expect(verify).not.toHaveBeenCalled()
  })

  it("rejects a token the verifier does not validate", async () => {
    const authenticate = createBearerAuthenticator(async () => undefined)

    await expect(
      authenticate(request("Bearer vencido"))
    ).resolves.toBeUndefined()
  })

  it("rejects verified claims without a usable sub", async () => {
    const authenticate = createBearerAuthenticator(async () => ({ sub: "" }))
    const numeric = createBearerAuthenticator(async () => ({ sub: 42 }))
    const absent = createBearerAuthenticator(async () => ({}))

    await expect(authenticate(request("Bearer x"))).resolves.toBeUndefined()
    await expect(numeric(request("Bearer x"))).resolves.toBeUndefined()
    await expect(absent(request("Bearer x"))).resolves.toBeUndefined()
  })

  it("builds the identity only from the verified sub", async () => {
    const authenticate = createBearerAuthenticator(async () => ({
      app_metadata: { role: "owner" },
      sub: "8f1c2c66-1a1e-4a53-9f1e-9c0b3b1a2d44",
      user_metadata: { tenant_id: "otro-tenant" },
    }))

    const actor = await authenticate(request("Bearer token-valido"))

    expect(actor).toEqual({
      credential: "token-valido",
      id: "8f1c2c66-1a1e-4a53-9f1e-9c0b3b1a2d44",
    })
  })

  it("propagates an infrastructure failure instead of granting access", async () => {
    const authenticate = createBearerAuthenticator(async () => {
      throw new Error("auth service unreachable")
    })

    await expect(authenticate(request("Bearer x"))).rejects.toThrowError(
      /unreachable/
    )
  })
})
