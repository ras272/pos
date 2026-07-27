import { describe, expect, it } from "vitest"

import { cajaContentSecurityPolicy } from "./csp.js"

const env = {
  apiUrl: "https://api.example.com",
  supabaseUrl: "https://project.supabase.co",
}

describe("cajaContentSecurityPolicy", () => {
  it("allows no inline script and no eval", () => {
    const policy = cajaContentSecurityPolicy(env)

    expect(policy).toContain("script-src 'self'")
    expect(policy).not.toContain("unsafe-inline")
    expect(policy).not.toContain("unsafe-eval")
  })

  it("allows only the exact Supabase and API origins", () => {
    const policy = cajaContentSecurityPolicy(env)

    expect(policy).toContain(
      "connect-src 'self' https://project.supabase.co https://api.example.com"
    )
  })

  it("keeps a URL with a path down to its origin", () => {
    const policy = cajaContentSecurityPolicy({
      ...env,
      supabaseUrl: "https://project.supabase.co/rest/v1",
    })

    expect(policy).toContain("connect-src 'self' https://project.supabase.co ")
  })

  it("refuses to build a policy with a missing origin", () => {
    expect(() =>
      cajaContentSecurityPolicy({ ...env, supabaseUrl: undefined })
    ).toThrowError(/VITE_SUPABASE_URL is required/)
    expect(() =>
      cajaContentSecurityPolicy({ ...env, apiUrl: undefined })
    ).toThrowError(/VITE_API_URL is required/)
  })

  it("refuses a wildcard or a non-URL origin", () => {
    expect(() =>
      cajaContentSecurityPolicy({ ...env, apiUrl: "https://*.example.com" })
    ).toThrowError(/cannot be a wildcard/)
    expect(() =>
      cajaContentSecurityPolicy({ ...env, apiUrl: "api.example.com" })
    ).toThrowError(/must be an absolute URL/)
  })

  it("closes the usual injection routes", () => {
    const policy = cajaContentSecurityPolicy(env)

    expect(policy).toContain("object-src 'none'")
    expect(policy).toContain("base-uri 'none'")
    expect(policy).toContain("frame-ancestors 'none'")
  })
})
