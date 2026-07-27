import { describe, expect, it } from "vitest"

import { createCors } from "./cors"

const policy = {
  allowedHeaders: ["Authorization", "Content-Type"],
  allowedMethods: ["GET", "POST", "OPTIONS"],
  allowedOrigins: ["https://admin.example.com", "https://caja.example.com"],
}

function request(origin: string | undefined, method = "POST") {
  return new Request("https://api.example.com/api/security-contract", {
    headers: origin ? { origin } : undefined,
    method,
  })
}

describe("createCors", () => {
  it("rejects a wildcard origin at construction", () => {
    expect(() => createCors({ ...policy, allowedOrigins: ["*"] })).toThrowError(
      /non-exact origins/
    )
    expect(() =>
      createCors({ ...policy, allowedOrigins: ["https://*.example.com"] })
    ).toThrowError(/non-exact origins/)
  })

  it("rejects an origin that carries a path or is not a URL", () => {
    expect(() =>
      createCors({
        ...policy,
        allowedOrigins: ["https://admin.example.com/app"],
      })
    ).toThrowError(/non-exact origins/)
    expect(() =>
      createCors({ ...policy, allowedOrigins: ["admin.example.com"] })
    ).toThrowError(/non-exact origins/)
  })

  it("requires at least one origin and one method", () => {
    expect(() => createCors({ ...policy, allowedOrigins: [] })).toThrowError(
      /at least one allowed origin/
    )
    expect(() => createCors({ ...policy, allowedMethods: [] })).toThrowError(
      /at least one allowed method/
    )
  })

  it("echoes an allowed origin and always declares Vary", () => {
    const cors = createCors(policy)
    const headers = new Headers()

    cors.decorate(headers, request("https://caja.example.com"))

    expect(headers.get("Access-Control-Allow-Origin")).toBe(
      "https://caja.example.com"
    )
    expect(headers.get("Vary")).toBe("Origin")
  })

  it("denies an unknown origin but still declares Vary", () => {
    const cors = createCors(policy)
    const headers = new Headers()

    cors.decorate(headers, request("https://atacante.example.com"))

    expect(headers.get("Access-Control-Allow-Origin")).toBeNull()
    expect(headers.get("Vary")).toBe("Origin")
  })

  it("denies the opaque null origin", () => {
    const cors = createCors(policy)
    const headers = new Headers()

    cors.decorate(headers, request("null"))

    expect(headers.get("Access-Control-Allow-Origin")).toBeNull()
  })

  it("leaves a same-origin request without CORS headers", () => {
    const cors = createCors(policy)
    const headers = new Headers()

    cors.decorate(headers, request(undefined))

    expect(headers.get("Access-Control-Allow-Origin")).toBeNull()
  })

  it("answers a preflight from an allowed origin with the exact policy", () => {
    const cors = createCors(policy)

    const response = cors.preflight(
      request("https://admin.example.com", "OPTIONS")
    )

    expect(response?.status).toBe(204)
    expect(response?.headers.get("Access-Control-Allow-Origin")).toBe(
      "https://admin.example.com"
    )
    expect(response?.headers.get("Access-Control-Allow-Methods")).toBe(
      "GET, POST, OPTIONS"
    )
    expect(response?.headers.get("Access-Control-Allow-Headers")).toBe(
      "Authorization, Content-Type"
    )
    expect(response?.headers.get("Access-Control-Max-Age")).toBe("600")
    expect(response?.headers.get("Vary")).toBe("Origin")
  })

  it("never allows credentials, because the API authenticates with bearer", () => {
    const cors = createCors(policy)

    const response = cors.preflight(
      request("https://admin.example.com", "OPTIONS")
    )

    expect(response?.headers.get("Access-Control-Allow-Credentials")).toBeNull()
  })

  it("refuses a preflight from an unknown origin", () => {
    const cors = createCors(policy)

    const response = cors.preflight(
      request("https://atacante.example.com", "OPTIONS")
    )

    expect(response?.status).toBe(403)
    expect(response?.headers.get("Access-Control-Allow-Origin")).toBeNull()
  })

  it("ignores requests that are not preflights", () => {
    const cors = createCors(policy)

    expect(cors.preflight(request("https://admin.example.com"))).toBeUndefined()
  })
})
