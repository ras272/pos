import { describe, expect, it } from "vitest"
import { readFile } from "node:fs/promises"
import path from "node:path"

import { findSecurityPatterns } from "../security-patterns.mjs"

describe("findSecurityPatterns", () => {
  it.each([
    [
      "legacy Supabase role key",
      "SUPABASE_KEY=eyJ.service_role.signature",
      "legacy service role",
    ],
    [
      "current Supabase secret key",
      "SUPABASE_KEY=sb_secret_realvalue123",
      "Supabase secret key",
    ],
    [
      "Postgres URL",
      "DATABASE_URL=postgresql://owner:password@db.example.com:5432/app",
      "database URL",
    ],
    [
      "Vercel token",
      "VERCEL_TOKEN=vercel_abcdefghijklmnopqrstuvwxyz123456",
      "Vercel token",
    ],
    [
      "private key",
      "-----BEGIN PRIVATE KEY-----",
      "certificate or private key material",
    ],
  ])("detects %s", (_label, content, expectedRule) => {
    const findings = findSecurityPatterns({
      filePath: "apps/api/.env",
      content,
    })

    expect(findings.map((finding) => finding.rule)).toContain(expectedRule)
  })

  it.each([
    ".env.example",
    "docs/security-examples.md",
    "scripts/__tests__/secret-fixture.ts",
    "apps/api/example.env",
  ])("does not flag documented examples or tests in %s", (filePath) => {
    const findings = findSecurityPatterns({
      filePath,
      content: "SUPABASE_KEY=sb_secret_example-only",
    })

    expect(findings).toEqual([])
  })

  it("does not flag the environment validator's pattern definitions", async () => {
    const filePath = path.resolve(
      import.meta.dirname,
      "../check-env-example.mjs"
    )
    const findings = findSecurityPatterns({
      filePath: "scripts/check-env-example.mjs",
      content: await readFile(filePath, "utf8"),
    })

    expect(findings).toEqual([])
  })
})
