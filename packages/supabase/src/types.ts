import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@workspace/database"

export type BrowserSupabaseClient = SupabaseClient<Database>
