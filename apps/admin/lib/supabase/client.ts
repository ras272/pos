import {
  createBrowserClient,
  type BrowserSupabaseClient,
} from "@workspace/supabase/browser"

import { publicConfig } from "./config"

/**
 * Cliente de navegador del backoffice. Reusa la fÃ¡brica compartida para que
 * exista un solo lugar donde se decide quÃ© clave y quÃ© tipos usa el browser.
 */
export function createClient(): BrowserSupabaseClient {
  return createBrowserClient(publicConfig())
}
