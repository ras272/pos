import { parsePublicEnv, type PublicEnv } from "@workspace/env/public"

// Se resuelve en el primer uso, no al importar: un build sin variables no
// revienta, pero una request sin ellas falla cerrado.
let cached: PublicEnv | undefined

export function publicConfig(): PublicEnv {
  cached ??= parsePublicEnv({
    SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  })
  return cached
}
