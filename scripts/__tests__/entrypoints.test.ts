import { mkdir, mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

import { describe, expect, it } from "vitest"

import { checkEntrypoints } from "../check-entrypoints.mjs"

const future = "2099-01-01"

async function fixture(files: Record<string, string>) {
  const root = await mkdtemp(path.join(tmpdir(), "entrypoints-"))

  await Promise.all(
    Object.entries(files).map(async ([relativePath, content]) => {
      const filePath = path.join(root, relativePath)
      await mkdir(path.dirname(filePath), { recursive: true })
      await writeFile(filePath, content)
    })
  )

  if (!("security/public-entrypoints.json" in files)) {
    const manifestPath = path.join(root, "security/public-entrypoints.json")
    await mkdir(path.dirname(manifestPath), { recursive: true })
    await writeFile(manifestPath, "[]\n")
  }

  return root
}

describe("checkEntrypoints", () => {
  it("rejects an unwrapped Route Handler export", async () => {
    const root = await fixture({
      "apps/api/app/orders/route.ts":
        "export async function POST() { return Response.json({ ok: true }) }\n",
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "apps/api/app/orders/route.ts: POST must directly call defineAuthenticatedRoute or definePublicRoute"
    )
  })

  it("accepts an authenticated Route Handler wrapper", async () => {
    const root = await fixture({
      "apps/api/app/orders/route.ts": [
        'import { defineAuthenticatedRoute } from "@workspace/api"',
        "export const POST = defineAuthenticatedRoute({})",
        "",
      ].join("\n"),
    })

    await expect(checkEntrypoints(root)).resolves.toEqual([])
  })

  it("rejects a local function pretending to be an approved wrapper", async () => {
    const root = await fixture({
      "apps/api/app/orders/route.ts": [
        "const defineAuthenticatedRoute = (value: unknown) => value",
        "export const GET = defineAuthenticatedRoute({})",
        "",
      ].join("\n"),
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "apps/api/app/orders/route.ts: GET must use defineAuthenticatedRoute imported from @workspace/api"
    )
  })

  it("checks JavaScript Route Handlers", async () => {
    const root = await fixture({
      "apps/api/app/orders/route.js":
        "export async function POST() { return Response.json({ ok: true }) }\n",
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "apps/api/app/orders/route.js: POST must directly call defineAuthenticatedRoute or definePublicRoute"
    )
  })

  it("requires an exact, current manifest record for a public route", async () => {
    const root = await fixture({
      "apps/api/app/(public)/health/[probe]/route.ts": [
        'import { definePublicRoute } from "@workspace/api"',
        "export const GET = definePublicRoute({})",
        "",
      ].join("\n"),
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "apps/api/app/(public)/health/[probe]/route.ts: public GET /health/[probe] is not listed"
    )
  })

  it("accepts a fully reviewed public route", async () => {
    const root = await fixture({
      "apps/api/app/(public)/health/route.ts": [
        'import { definePublicRoute } from "@workspace/api"',
        "export const GET = definePublicRoute({})",
        "",
      ].join("\n"),
      "security/public-entrypoints.json": `${JSON.stringify(
        [
          {
            method: "GET",
            path: "/health",
            reason: "Infrastructure health probe",
            owner: "platform",
            expiresOn: future,
            noTenantData: true,
            noMutation: true,
          },
        ],
        null,
        2
      )}\n`,
    })

    await expect(
      checkEntrypoints(root, { now: new Date("2026-07-26T00:00:00Z") })
    ).resolves.toEqual([])
  })

  it("omits parallel route folders from public manifest paths", async () => {
    const root = await fixture({
      "apps/api/app/@internal/health/route.ts": [
        'import { definePublicRoute } from "@workspace/api"',
        "export const GET = definePublicRoute({})",
        "",
      ].join("\n"),
      "security/public-entrypoints.json": `${JSON.stringify([
        {
          method: "GET",
          path: "/health",
          reason: "Infrastructure health probe",
          owner: "platform",
          expiresOn: future,
          noTenantData: true,
          noMutation: true,
        },
      ])}\n`,
    })

    await expect(checkEntrypoints(root)).resolves.toEqual([])
  })

  it("rejects expired, malformed, and stale public manifest entries", async () => {
    const root = await fixture({
      "security/public-entrypoints.json": `${JSON.stringify([
        {
          method: "GET",
          path: "/removed",
          reason: "old",
          owner: "platform",
          expiresOn: "2020-01-01",
          noTenantData: false,
          noMutation: false,
        },
      ])}\n`,
    })

    const errors = await checkEntrypoints(root, {
      now: new Date("2026-07-26T00:00:00Z"),
    })

    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("expiresOn is expired"),
        expect.stringContaining("noTenantData must be true"),
        expect.stringContaining("mutationJustification is required"),
        expect.stringContaining("does not match a definePublicRoute export"),
      ])
    )
  })

  it("rejects impossible calendar dates in the public manifest", async () => {
    const root = await fixture({
      "security/public-entrypoints.json": `${JSON.stringify([
        {
          method: "GET",
          path: "/future",
          reason: "Invalid date fixture",
          owner: "platform",
          expiresOn: "2099-02-30",
          noTenantData: true,
          noMutation: true,
        },
      ])}\n`,
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "security/public-entrypoints.json[0]: expiresOn must be an ISO date"
    )
  })

  it("rejects unwrapped exports in a use server module", async () => {
    const root = await fixture({
      "apps/admin/app/actions.ts": [
        "'use server'",
        "export async function saveOrder() {}",
        "",
      ].join("\n"),
    })

    await expect(checkEntrypoints(root)).resolves.toContain(
      "apps/admin/app/actions.ts: saveOrder must directly call defineAuthenticatedAction"
    )
  })

  it("accepts an authenticated Server Action wrapper", async () => {
    const root = await fixture({
      "apps/admin/app/actions.ts": [
        "'use server'",
        'import { defineAuthenticatedAction } from "@workspace/api"',
        "export const saveOrder = defineAuthenticatedAction({})",
        "",
      ].join("\n"),
    })

    await expect(checkEntrypoints(root)).resolves.toEqual([])
  })
})
