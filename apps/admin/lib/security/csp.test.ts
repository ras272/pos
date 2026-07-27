import { describe, expect, it } from "vitest"

import { contentSecurityPolicy, createNonce, hardeningHeaders } from "./csp"

const base = {
  connectSrc: ["https://project.supabase.co"],
  environment: "production" as const,
  nonce: "n0nc3",
}

function directive(policy: string, name: string): string | undefined {
  return policy
    .split("; ")
    .find((entry) => entry === name || entry.startsWith(`${name} `))
}

describe("createNonce", () => {
  it("produces a different value on every call", () => {
    expect(createNonce()).not.toBe(createNonce())
  })
})

describe("contentSecurityPolicy", () => {
  it("never allows inline or eval in production", () => {
    const policy = contentSecurityPolicy(base)

    expect(policy).not.toContain("unsafe-inline")
    expect(policy).not.toContain("unsafe-eval")
  })

  it("binds scripts and styles to the request nonce", () => {
    const policy = contentSecurityPolicy(base)

    expect(directive(policy, "script-src")).toBe(
      "script-src 'self' 'nonce-n0nc3' 'strict-dynamic'"
    )
    expect(directive(policy, "style-src")).toBe(
      "style-src 'self' 'nonce-n0nc3'"
    )
  })

  it("closes the usual injection routes", () => {
    const policy = contentSecurityPolicy(base)

    expect(directive(policy, "object-src")).toBe("object-src 'none'")
    expect(directive(policy, "base-uri")).toBe("base-uri 'none'")
    expect(directive(policy, "frame-ancestors")).toBe("frame-ancestors 'none'")
    expect(directive(policy, "form-action")).toBe("form-action 'self'")
    expect(policy).toContain("upgrade-insecure-requests")
  })

  it("allows only the exact origins it was given", () => {
    const policy = contentSecurityPolicy({
      ...base,
      connectSrc: ["https://project.supabase.co", "https://api.example.com"],
    })

    expect(directive(policy, "connect-src")).toBe(
      "connect-src 'self' https://project.supabase.co https://api.example.com"
    )
  })

  it("refuses a wildcard, a path or a non-URL as connect-src", () => {
    expect(() =>
      contentSecurityPolicy({ ...base, connectSrc: ["*"] })
    ).toThrowError(/wildcard/)
    expect(() =>
      contentSecurityPolicy({ ...base, connectSrc: ["https://*.supabase.co"] })
    ).toThrowError(/wildcard/)
    expect(() =>
      contentSecurityPolicy({
        ...base,
        connectSrc: ["https://project.supabase.co/rest"],
      })
    ).toThrowError(/exact origin/)
    expect(() =>
      contentSecurityPolicy({ ...base, connectSrc: ["project.supabase.co"] })
    ).toThrowError(/absolute origin/)
  })

  it("relaxes only what React needs in development", () => {
    const policy = contentSecurityPolicy({
      ...base,
      environment: "development",
    })

    expect(directive(policy, "script-src")).toContain("'unsafe-eval'")
    expect(directive(policy, "style-src")).toBe(
      "style-src 'self' 'unsafe-inline'"
    )
  })
})

describe("hardeningHeaders", () => {
  it("sends HSTS only in production", () => {
    const production = hardeningHeaders("production").map((h) => h.key)
    const development = hardeningHeaders("development").map((h) => h.key)

    expect(production).toContain("Strict-Transport-Security")
    expect(development).not.toContain("Strict-Transport-Security")
  })

  it("denies sniffing, framing and referrer leakage", () => {
    const headers = new Map(
      hardeningHeaders("production").map((h) => [h.key, h.value])
    )

    expect(headers.get("X-Content-Type-Options")).toBe("nosniff")
    expect(headers.get("X-Frame-Options")).toBe("DENY")
    expect(headers.get("Referrer-Policy")).toBe("no-referrer")
    expect(headers.get("Permissions-Policy")).toContain("camera=()")
  })

  it("keeps an authenticated response out of any shared cache", () => {
    const headers = new Map(
      hardeningHeaders("production").map((h) => [h.key, h.value])
    )

    expect(headers.get("Cache-Control")).toBe("private, no-store")
  })
})
