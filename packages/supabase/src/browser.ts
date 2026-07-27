import { createClient } from "@supabase/supabase-js"

import type { Database } from "@workspace/database"
import type { PublicEnv } from "@workspace/env/public"

import type { BrowserSupabaseClient } from "./types.js"

export function createBrowserClient(config: PublicEnv): BrowserSupabaseClient {
  return createClient<Database>(
    config.supabaseUrl,
    config.supabasePublishableKey
  )
}

export type { BrowserSupabaseClient } from "./types.js"
