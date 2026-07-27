import { describe, expect, it } from "vitest"

import { PublicEnvValidationError, parsePublicEnv } from "./public"

const validEnv = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abcdefghijklmnopqrstuvwxyz",
}

function expectInvalid(input: unknown, message: string) {
  try {
    parsePublicEnv(input)
    throw new Error("Expected public environment validation to fail")
  } catch (error) {
    expect(error).toBeInstanceOf(PublicEnvValidationError)
    expect((error as Error).message).toBe(message)
  }
}

describe("parsePublicEnv", () => {
  it("normalizes a valid injected record", () => {
    const config = parsePublicEnv(validEnv)

    expect(config).toEqual({
      supabaseUrl: validEnv.SUPABASE_URL,
      supabasePublishableKey: validEnv.SUPABASE_PUBLISHABLE_KEY,
    })
    expect(Object.isFrozen(config)).toBe(true)
  })

  it.each([
    [
      { SUPABASE_PUBLISHABLE_KEY: validEnv.SUPABASE_PUBLISHABLE_KEY },
      "SUPABASE_URL is required",
    ],
    [
      { SUPABASE_URL: validEnv.SUPABASE_URL },
      "SUPABASE_PUBLISHABLE_KEY is required",
    ],
  ])("rejects a missing browser value", (input, detail) => {
    expectInvalid(input, `Invalid public environment: ${detail}`)
  })

  it.each(["not-a-url", "ftp://example.supabase.co", "https://"])(
    "rejects malformed or unsupported URLs: %s",
    (url) => {
      expectInvalid(
        { ...validEnv, SUPABASE_URL: url },
        "Invalid public environment: SUPABASE_URL must be an HTTP(S) URL"
      )
    }
  )

  it("accepts the local HTTP Supabase URL", () => {
    expect(
      parsePublicEnv({ ...validEnv, SUPABASE_URL: "http://127.0.0.1:54321" })
        .supabaseUrl
    ).toBe("http://127.0.0.1:54321")
  })

  it.each(["publishable-key", "anon"])(
    "rejects malformed publishable keys",
    (key) => {
      expectInvalid(
        { ...validEnv, SUPABASE_PUBLISHABLE_KEY: key },
        "Invalid public environment: SUPABASE_PUBLISHABLE_KEY must use the sb_publishable_ format"
      )
    }
  )

  it.each([
    "service_role",
    "sb_secret_abcdefghijklmnopqrstuvwxyz",
    "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature",
  ])("rejects server-only Supabase values", (key) => {
    expectInvalid(
      { ...validEnv, SUPABASE_PUBLISHABLE_KEY: key },
      "Invalid public environment: server-only values are forbidden"
    )
  })

  it.each([
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "DATABASE_URL",
    "JWT_SECRET",
    "PRIVATE_KEY",
    "AUTHORIZATION",
    "COOKIE",
  ])("rejects server-only field names: %s", (name) => {
    expectInvalid(
      { ...validEnv, [name]: "redacted-test-value" },
      "Invalid public environment: server-only fields are forbidden"
    )
  })

  it("never serializes a rejected secret into its error", () => {
    const secret = "sb_secret_do-not-print-this-value"

    try {
      parsePublicEnv({ ...validEnv, SUPABASE_PUBLISHABLE_KEY: secret })
    } catch (error) {
      expect(String(error)).not.toContain(secret)
    }
  })

  it("rejects unknown public fields", () => {
    expectInvalid(
      { ...validEnv, PUBLIC_LABEL: "extra" },
      "Invalid public environment: unexpected fields are forbidden"
    )
  })
})
