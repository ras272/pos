import { createHash } from "node:crypto"
import { mkdir, mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

import { describe, expect, it } from "vitest"

import { checkFileSizes } from "../check-file-size.mjs"

async function fixture(files: Record<string, string>) {
  const root = await mkdtemp(path.join(tmpdir(), "file-size-"))
  await Promise.all(
    Object.entries(files).map(async ([relativePath, content]) => {
      const filePath = path.join(root, relativePath)
      await mkdir(path.dirname(filePath), { recursive: true })
      await writeFile(filePath, content)
    })
  )
  return root
}

const oversized = Array.from({ length: 251 }, () => "export {};").join("\n")

describe("checkFileSizes", () => {
  it("rejects handwritten source files over 250 lines", async () => {
    const root = await fixture({ "packages/core/src/large.ts": oversized })

    await expect(checkFileSizes(root)).resolves.toContain(
      "packages/core/src/large.ts: 251 lines exceeds the 250-line limit"
    )
  })

  it("applies the source limit to JavaScript files", async () => {
    const root = await fixture({ "packages/core/src/large.js": oversized })

    await expect(checkFileSizes(root)).resolves.toContain(
      "packages/core/src/large.js: 251 lines exceeds the 250-line limit"
    )
  })

  it("excludes hash-identified generated sources and generated categories", async () => {
    const hash = createHash("sha256").update(oversized).digest("hex")
    const root = await fixture({
      "packages/database/src/database.types.ts": oversized,
      "packages/ui/src/components/generated.tsx": oversized,
      "packages/core/src/large.test.ts": oversized,
      "supabase/migrations/001_init.ts": oversized,
      "docs/example.mjs": oversized,
      "security/file-size-exceptions.json": "[]\n",
      "security/generated-file-hashes.json": `${JSON.stringify([
        {
          path: "packages/ui/src/components/generated.tsx",
          sha256: hash,
        },
      ])}\n`,
    })

    await expect(checkFileSizes(root)).resolves.toEqual([])
  })

  it("does not exempt handwritten components in the shadcn directory", async () => {
    const root = await fixture({
      "packages/ui/src/components/handwritten.tsx": oversized,
      "security/file-size-exceptions.json": "[]\n",
      "security/generated-file-hashes.json": "[]\n",
    })

    await expect(checkFileSizes(root)).resolves.toContain(
      "packages/ui/src/components/handwritten.tsx: 251 lines exceeds the 250-line limit"
    )
  })

  it("validates exceptions and rejects stale or expired records", async () => {
    const root = await fixture({
      "packages/core/src/small.ts": "export {}\n",
      "security/file-size-exceptions.json": `${JSON.stringify([
        {
          path: "packages/core/src/small.ts",
          reason: "Temporary decomposition",
          owner: "platform",
          expiresOn: "2020-01-01",
        },
      ])}\n`,
    })

    const errors = await checkFileSizes(root, {
      now: new Date("2026-07-26T00:00:00Z"),
    })
    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("expiresOn is expired"),
        expect.stringContaining("does not match an oversized source file"),
      ])
    )
  })

  it("rejects impossible calendar dates in exceptions", async () => {
    const root = await fixture({
      "packages/core/src/large.ts": oversized,
      "security/file-size-exceptions.json": `${JSON.stringify([
        {
          path: "packages/core/src/large.ts",
          reason: "Invalid date fixture",
          owner: "platform",
          expiresOn: "2099-02-30",
        },
      ])}\n`,
    })

    await expect(checkFileSizes(root)).resolves.toContain(
      "security/file-size-exceptions.json[0]: expiresOn must be an ISO date"
    )
  })
})
