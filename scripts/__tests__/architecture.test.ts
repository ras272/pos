import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

import { describe, expect, it } from "vitest"

import { checkArchitecture } from "../check-architecture.mjs"
import { validateEnvExample } from "../check-env-example.mjs"
import { checkFileSizes } from "../check-file-size.mjs"
import { checkWorkflows } from "../check-workflows.mjs"

async function fixture(files: Record<string, string>) {
  const root = await mkdtemp(path.join(tmpdir(), "architecture-"))

  await Promise.all(
    Object.entries(files).map(async ([relativePath, content]) => {
      const filePath = path.join(root, relativePath)
      await mkdir(path.dirname(filePath), { recursive: true })
      await writeFile(filePath, content)
    })
  )

  return root
}

describe("checkArchitecture", () => {
  it("rejects packages importing applications", async () => {
    const root = await fixture({
      "packages/data/src/index.ts":
        'export { page } from "../../../apps/web/app/page"\n',
    })

    await expect(checkArchitecture(root)).resolves.toContain(
      "packages/data/src/index.ts: packages cannot import from apps"
    )
  })

  it.each(["server-only", "node:fs", "next/headers", "@workspace/env/server"])(
    "rejects %s in the browser-only caja application",
    async (moduleName) => {
      const root = await fixture({
        "apps/caja/src/main.ts": `import ${JSON.stringify(moduleName)}\n`,
      })

      await expect(checkArchitecture(root)).resolves.toContain(
        `apps/caja/src/main.ts: caja cannot import ${moduleName}`
      )
    }
  )

  it("allows an explicitly browser-safe package subpath in caja", async () => {
    const root = await fixture({
      "apps/caja/src/main.ts":
        'import { Button } from "@workspace/ui/components/button"\n',
    })

    await expect(checkArchitecture(root)).resolves.toEqual([])
  })

  it("rejects Route Handlers outside apps/api", async () => {
    const root = await fixture({
      "apps/web/app/api/route.ts": "export const GET = () => new Response()\n",
    })

    await expect(checkArchitecture(root)).resolves.toContain(
      "apps/web/app/api/route.ts: Route Handlers are allowed only in apps/api"
    )
  })
})

describe("checkFileSizes", () => {
  it("rejects handwritten source files over 250 lines", async () => {
    const root = await fixture({
      "packages/core/src/large.ts": Array.from(
        { length: 251 },
        () => "export {};"
      ).join("\n"),
    })

    await expect(checkFileSizes(root)).resolves.toContain(
      "packages/core/src/large.ts: 251 lines exceeds the 250-line limit"
    )
  })

  it("excludes generated database types, shadcn sources, tests, migrations, and docs", async () => {
    const content = Array.from({ length: 251 }, () => "export {};").join("\n")
    const root = await fixture({
      "packages/database/src/database.types.ts": content,
      "packages/ui/src/components/generated.tsx": content,
      "packages/core/src/large.test.ts": content,
      "supabase/migrations/001_init.ts": content,
      "docs/example.mjs": content,
      "security/file-size-exceptions.json": "[]\n",
    })

    await expect(checkFileSizes(root)).resolves.toEqual([])
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
})

describe("validateEnvExample", () => {
  it("requires safe public placeholders and a gitignore exception", async () => {
    const root = await fixture({
      ".env.example":
        "NEXT_PUBLIC_SUPABASE_URL=https://real-project.supabase.co\n",
      ".gitignore": ".env*\n",
    })

    const errors = await validateEnvExample(root)

    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
        expect.stringContaining("must contain a placeholder"),
        expect.stringContaining("!.env.example"),
      ])
    )
  })
})

describe("checkWorkflows", () => {
  it("allows an explicitly not-yet-created workflow directory", async () => {
    const root = await fixture({})

    await expect(checkWorkflows(root)).resolves.toEqual([])
  })

  it("rejects mutable actions and dangerous workflow constructs once workflows exist", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request_target",
        "jobs:",
        "  quality:",
        "    runs-on: self-hosted",
        "    steps:",
        "      - uses: actions/checkout@v4",
        "",
      ].join("\n"),
    })

    const errors = await checkWorkflows(root)

    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("pull_request_target"),
        expect.stringContaining("self-hosted"),
        expect.stringContaining("immutable 40-character SHA"),
      ])
    )
  })
})

describe("repository tooling contract", () => {
  const repositoryRoot = path.resolve(import.meta.dirname, "../..")

  it("pins the runtime and required tools and exposes every root gate", async () => {
    const packageJson = JSON.parse(
      await readFile(path.join(repositoryRoot, "package.json"), "utf8")
    )
    const requiredScripts = [
      "format:check",
      "test",
      "test:db",
      "db:types",
      "db:types:check",
      "security",
      "check",
    ]

    expect(packageJson.engines.node).toBe("24.18.0")
    expect(packageJson.devDependencies.supabase).toBe("2.109.1")
    expect(packageJson.devDependencies.vitest).toBe("4.1.10")
    expect(Object.keys(packageJson.scripts)).toEqual(
      expect.arrayContaining(requiredScripts)
    )
    expect(packageJson.scripts.lint).toContain("--max-warnings=0")
    await expect(
      readFile(path.join(repositoryRoot, ".node-version"), "utf8")
    ).resolves.toBe("24.18.0\n")
  })

  it("declares the Turbo test task and safe tracked repository contracts", async () => {
    const turbo = JSON.parse(
      await readFile(path.join(repositoryRoot, "turbo.json"), "utf8")
    )
    const gitignore = await readFile(
      path.join(repositoryRoot, ".gitignore"),
      "utf8"
    )

    expect(turbo.tasks.test).toMatchObject({ dependsOn: ["^test"] })
    expect(gitignore).toMatch(/^!\.env\.example\s*$/m)
    await expect(validateEnvExample(repositoryRoot)).resolves.toEqual([])
    await expect(
      readFile(
        path.join(repositoryRoot, "security/file-size-exceptions.json"),
        "utf8"
      )
    ).resolves.toBe("[]\n")
    await expect(
      readFile(
        path.join(repositoryRoot, "security/public-entrypoints.json"),
        "utf8"
      )
    ).resolves.toBe("[]\n")
  })

  it("fails new warnings while localizing the generated UI warning baseline", async () => {
    const baseConfig = await readFile(
      path.join(repositoryRoot, "packages/eslint-config/base.js"),
      "utf8"
    )
    const uiConfig = await readFile(
      path.join(repositoryRoot, "packages/ui/eslint.config.js"),
      "utf8"
    )

    expect(baseConfig).not.toContain("eslint-plugin-only-warn")
    expect(uiConfig).toContain("src/components/carousel.tsx")
    expect(uiConfig).toContain("src/hooks/use-mobile.ts")
    expect(uiConfig).toContain('"react-hooks/set-state-in-effect": "off"')
  })
})
