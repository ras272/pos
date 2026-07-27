import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"

import { describe, expect, it } from "vitest"
import { build } from "vite"

describe("server environment entry", () => {
  it("marks the module with server-only", async () => {
    const source = await readFile(
      new URL("./server.ts", import.meta.url),
      "utf8"
    )

    expect(source).toMatch(/^import ["']server-only["']/m)
  })

  it("fails a Vite browser build that imports the server entry", async () => {
    const input = fileURLToPath(
      new URL("./fixtures/browser-server-entry.ts", import.meta.url)
    )

    await expect(
      build({
        build: { rollupOptions: { input }, write: false },
        configFile: false,
        logLevel: "silent",
      })
    ).rejects.toThrow(/server-entry-is-not-browser-safe/)
  })
})
