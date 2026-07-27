import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import { POST } from "./route"

function post(authorization?: string) {
  return new Request("https://api.example.com/api/security-contract", {
    body: JSON.stringify({ subject: "actor-1" }),
    headers: {
      "content-type": "application/json",
      ...(authorization ? { authorization } : {}),
    },
    method: "POST",
  })
}

describe("POST /api/security-contract", () => {
  beforeEach(() => {
    // La auditorÃ­a real escribe en stdout; acÃ¡ solo interesa la respuesta.
    vi.spyOn(process.stdout, "write").mockImplementation(() => true)
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllEnvs()
  })

  it("refuses an unauthenticated request without touching the handler", async () => {
    const response = await POST(post())

    expect(response.status).toBe(401)
    expect(await response.json()).toEqual({
      error: { code: "unauthenticated" },
      requestId: expect.any(String),
    })
  })

  it("never caches an authenticated endpoint response", async () => {
    const response = await POST(post())

    expect(response.headers.get("Cache-Control")).toBe("private, no-store")
    expect(response.headers.get("X-Request-Id")).toEqual(expect.any(String))
  })

  it("fails closed when the Supabase configuration is missing", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", undefined)
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", undefined)

    const response = await POST(post("Bearer cualquier-token"))

    expect(response.status).toBe(503)
    expect(await response.json()).toEqual({
      error: { code: "authentication_unavailable" },
      requestId: expect.any(String),
    })
  })

  it("never leaks the bearer token back to the caller", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", undefined)
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", undefined)

    const response = await POST(post("Bearer token-secreto"))

    expect(await response.text()).not.toContain("token-secreto")
  })
})
