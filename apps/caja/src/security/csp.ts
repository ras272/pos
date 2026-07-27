export type CajaEnv = Readonly<{
  apiUrl?: string
  supabaseUrl?: string
}>

function exactOrigin(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`${name} is required to build the caja CSP`)
  }
  if (value.includes("*")) {
    throw new Error(`${name} cannot be a wildcard: ${value}`)
  }
  let url: URL
  try {
    url = new URL(value)
  } catch {
    throw new Error(`${name} must be an absolute URL: ${value}`)
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`${name} must be an HTTP(S) URL: ${value}`)
  }
  return url.origin
}

/**
 * CSP estática de la caja. Es una SPA que se sirve como archivos: no hay
 * servidor que genere un nonce por request, así que no se admite ningún script
 * inline y todo el JavaScript sale del propio origen.
 */
export function cajaContentSecurityPolicy(env: CajaEnv): string {
  const supabase = exactOrigin("VITE_SUPABASE_URL", env.supabaseUrl)
  const api = exactOrigin("VITE_API_URL", env.apiUrl)

  return [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' blob: data:",
    "font-src 'self'",
    `connect-src 'self' ${supabase} ${api}`,
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ].join("; ")
}
