import { NextRequest } from "next/server"
import { describe, expect, it, vi } from "vitest"

import { updateSession } from "./proxy"

function request(cookie?: string) {
  return new NextRequest("https://admin.example.com/panel", {
    headers: cookie ? { cookie } : undefined,
  })
}

describe("updateSession", () => {
  it("hands the request cookies to the refresh", async () => {
    const seen: { name: string; value: string }[][] = []

    await updateSession(request("sb-access-token=abc"), async (bridge) => {
      seen.push(bridge.getAll())
    })

    expect(seen[0]).toEqual([{ name: "sb-access-token", value: "abc" }])
  })

  it("propagates every refreshed cookie to the browser", async () => {
    const response = await updateSession(request(), async (bridge) => {
      bridge.setAll([
        { name: "sb-access-token", options: { path: "/" }, value: "nuevo" },
        { name: "sb-refresh-token", options: { path: "/" }, value: "rotado" },
      ])
    })

    expect(response.cookies.get("sb-access-token")?.value).toBe("nuevo")
    expect(response.cookies.get("sb-refresh-token")?.value).toBe("rotado")
  })

  it("propagates the cache headers that keep a session out of a shared cache", async () => {
    const response = await updateSession(request(), async (bridge) => {
      bridge.setAll(
        [{ name: "sb-access-token", options: {}, value: "nuevo" }],
        {
          "Cache-Control":
            "private, no-cache, no-store, must-revalidate, max-age=0",
          Expires: "0",
          Pragma: "no-cache",
        }
      )
    })

    expect(response.headers.get("Cache-Control")).toBe(
      "private, no-cache, no-store, must-revalidate, max-age=0"
    )
    expect(response.headers.get("Expires")).toBe("0")
    expect(response.headers.get("Pragma")).toBe("no-cache")
  })

  it("stays optimistic when the refresh fails instead of blocking the request", async () => {
    const response = await updateSession(request(), async () => {
      throw new Error("supabase unreachable")
    })

    expect(response.status).toBe(200)
  })

  it("does not invent cookies when there is no session to refresh", async () => {
    const refresh = vi.fn(async () => undefined)

    const response = await updateSession(request(), refresh)

    expect(refresh).toHaveBeenCalledTimes(1)
    expect(response.cookies.getAll()).toEqual([])
  })
})
