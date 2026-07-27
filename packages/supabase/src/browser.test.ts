import { expectTypeOf } from "vitest"
import { describe, expect, it } from "vitest"

import type { PublicEnv } from "@workspace/env/public"
import {
  createBrowserClient,
  type BrowserSupabaseClient,
} from "@workspace/supabase/browser"

const config: PublicEnv = {
  supabaseUrl: "https://example.supabase.co",
  supabasePublishableKey: "sb_publishable_abcdefghijklmnopqrstuvwxyz",
}

describe("createBrowserClient", () => {
  it("creates a generated-Database browser client from injected public config", () => {
    const client = createBrowserClient(config)

    expect(Reflect.get(client, "supabaseUrl")).toBe(config.supabaseUrl)
    expect(Reflect.get(client, "supabaseKey")).toBe(
      config.supabasePublishableKey
    )
    expectTypeOf(client).toEqualTypeOf<BrowserSupabaseClient>()
    expectTypeOf(client.from("tenants")).not.toBeAny()
  })

  it("exposes no request-header or secret-client options", () => {
    expectTypeOf(createBrowserClient).parameters.toEqualTypeOf<[PublicEnv]>()
  })
})
