import { describe, expect, it } from "vitest"

import { apiSecurityHeaders } from "./headers"

function map(environment: "development" | "production" | "test") {
  return new Map(apiSecurityHeaders(environment).map((h) => [h.key, h.value]))
}

describe("apiSecurityHeaders", () => {
  it("sends HSTS only in production", () => {
    expect(map("production").has("Strict-Transport-Security")).toBe(true)
    expect(map("development").has("Strict-Transport-Security")).toBe(false)
  })

  it("forbids a JSON response from loading or running anything", () => {
    expect(map("production").get("Content-Security-Policy")).toBe(
      "default-src 'none'; frame-ancestors 'none'"
    )
  })

  it("denies sniffing, framing and referrer leakage", () => {
    const headers = map("production")

    expect(headers.get("X-Content-Type-Options")).toBe("nosniff")
    expect(headers.get("X-Frame-Options")).toBe("DENY")
    expect(headers.get("Referrer-Policy")).toBe("no-referrer")
    expect(headers.get("Permissions-Policy")).toContain("microphone=()")
  })

  it("keeps every API response out of a shared cache", () => {
    expect(map("production").get("Cache-Control")).toBe("private, no-store")
  })
})
