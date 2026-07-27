import { parsePublicEnv } from "@workspace/env/server"

export const config = parsePublicEnv({
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_browser-boundary-fixture",
  SUPABASE_URL: "https://example.supabase.co",
})
