import { describe, expect, it } from "vitest"

import { webSecurityHeaders } from "./headers"

function map(environment: "development" | "production" | "test") {
  return new Map(webSecurityHeaders(environment).map((h) => [h.key, h.value]))
}

describe("webSecurityHeaders", () => {
  it("sends HSTS only in production", () => {
    expect(map("production").has("Strict-Transport-Security")).toBe(true)
    expect(map("development").has("Strict-Transport-Security")).toBe(false)
  })

  it("denies sniffing and framing", () => {
    const headers = map("production")

    expect(headers.get("X-Content-Type-Options")).toBe("nosniff")
    expect(headers.get("X-Frame-Options")).toBe("DENY")
  })

  it("keeps the referrer within origin boundaries", () => {
    expect(map("production").get("Referrer-Policy")).toBe(
      "strict-origin-when-cross-origin"
    )
  })

  it("ships no CSP rather than a permissive one that only looks protective", () => {
    expect(map("production").has("Content-Security-Policy")).toBe(false)
    const values = [...map("production").values()].join(" ")
    expect(values).not.toContain("unsafe-inline")
  })
})
