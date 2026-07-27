import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"

import { describe, expect, it } from "vitest"

import { checkArchitecture } from "../check-architecture.mjs"
import { validateEnvExample } from "../check-env-example.mjs"
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

  it("allows Node-based tooling imports in root caja config files", async () => {
    const root = await fixture({
      "apps/caja/eslint.config.js":
        'import config from "@workspace/eslint-config/react-internal"\nexport default config\n',
    })

    await expect(checkArchitecture(root)).resolves.toEqual([])
  })

  it("rejects unapproved external runtime packages in caja", async () => {
    const root = await fixture({
      "apps/caja/src/main.ts": 'import { Pool } from "pg"\n',
    })

    await expect(checkArchitecture(root)).resolves.toContain(
      "apps/caja/src/main.ts: caja cannot import pg"
    )
  })

  it("rejects Route Handlers outside apps/api", async () => {
    const root = await fixture({
      "apps/web/app/api/route.ts": "export const GET = () => new Response()\n",
    })

    await expect(checkArchitecture(root)).resolves.toContain(
      "apps/web/app/api/route.ts: Route Handlers are allowed only in apps/api"
    )
  })

  it("rejects JavaScript Route Handlers outside apps/api", async () => {
    const root = await fixture({
      "apps/web/app/api/route.js": "export const GET = () => new Response()\n",
    })

    await expect(checkArchitecture(root)).resolves.toContain(
      "apps/web/app/api/route.js: Route Handlers are allowed only in apps/api"
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

  it("rejects unknown variables and secret values in examples", async () => {
    const root = await fixture({
      ".env.example": [
        "NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co",
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "VITE_API_URL=https://api.example.com",
        "VITE_SUPABASE_URL=https://your-project.supabase.co",
        "VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "FOO=sb_secret_example-real-secret",
        "",
      ].join("\n"),
      ".gitignore": ".env*\n!.env.example\n",
    })

    const errors = await validateEnvExample(root)
    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("FOO is not an approved public variable"),
        expect.stringContaining("FOO contains a forbidden secret value"),
      ])
    )
  })

  it("rejects duplicate variables that could hide an unsafe value", async () => {
    const root = await fixture({
      ".env.example": [
        "NEXT_PUBLIC_SUPABASE_URL=https://real-project.supabase.co",
        "NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co",
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "VITE_API_URL=https://api.example.com",
        "VITE_SUPABASE_URL=https://your-project.supabase.co",
        "VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "",
      ].join("\n"),
      ".gitignore": ".env*\n!.env.example\n",
    })

    await expect(validateEnvExample(root)).resolves.toContain(
      ".env.example: NEXT_PUBLIC_SUPABASE_URL must not be declared more than once"
    )
  })

  it("rejects a later gitignore rule that hides the example again", async () => {
    const root = await fixture({
      ".env.example": [
        "NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co",
        "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "VITE_API_URL=https://api.example.com",
        "VITE_SUPABASE_URL=https://your-project.supabase.co",
        "VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_replace-me",
        "",
      ].join("\n"),
      ".gitignore": ".env*\n!.env.example\n.env*\n",
    })

    await expect(validateEnvExample(root)).resolves.toContain(
      ".gitignore: .env.example must remain unignored after all rules"
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

  it("rejects multiline secret use and untrusted run interpolation", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: |",
        '          echo "${{ secrets.DEPLOY_TOKEN }}"',
        '          echo "${{ github.actor }}"',
        "",
      ].join("\n"),
    })

    const errors = await checkWorkflows(root)
    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("workflow secret contexts are forbidden"),
        expect.stringContaining("untrusted event data"),
      ])
    )
  })

  it("rejects commented write permissions", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "  pull-requests: write # not allowed",
        "jobs: {}",
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: workflow permissions must remain read-only"
    )
  })

  it("rejects quoted write permission values", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "  pull-requests: 'write'",
        '  "issues": "write"',
        "jobs: {}",
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: workflow permissions must remain read-only"
    )
  })

  it("rejects bracket and function access to sensitive workflow contexts", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run : echo \"${{ secrets['DEPLOY_TOKEN'] }}\"",
        "      - run: |",
        "          echo \"${{ github['actor'] }}\"",
        "          printf '%s' \"${{ toJSON(secrets) }}\"",
        "",
      ].join("\n"),
    })

    const errors = await checkWorkflows(root)
    expect(errors).toEqual(
      expect.arrayContaining([
        expect.stringContaining("workflow secret contexts are forbidden"),
        expect.stringContaining("untrusted event data"),
      ])
    )
  })

  it("rejects untrusted interpolation in explicit-indent block scalars", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: |-2",
        '          echo "${{ github.actor }}"',
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: untrusted event data cannot be interpolated into run scripts"
    )
  })

  it("rejects untrusted event data passed indirectly through env", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    runs-on: ubuntu-latest",
        "    env:",
        "      TITLE: ${{ github.event.pull_request.title }}",
        "    steps:",
        '      - run: eval "$TITLE"',
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: untrusted event data cannot be interpolated into run scripts"
    )
  })

  it("rejects dynamic runner selection that could resolve to self-hosted", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    strategy:",
        "      matrix:",
        "        runner: [ubuntu-latest, self-hosted]",
        "    runs-on: ${{ matrix.runner }}",
        "    steps: []",
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: dynamic runs-on values are forbidden"
    )
  })

  it("rejects dynamic access to GitHub context properties", async () => {
    const root = await fixture({
      ".github/workflows/quality.yml": [
        "on: pull_request",
        "permissions:",
        "  contents: read",
        "jobs:",
        "  quality:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo \"${{ github[format('event')] }}\"",
        "",
      ].join("\n"),
    })

    await expect(checkWorkflows(root)).resolves.toContain(
      ".github/workflows/quality.yml: untrusted event data cannot be interpolated into run scripts"
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
