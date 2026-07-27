/**
 * CORS de origen exacto. No existe comodín: un origen desconocido no recibe
 * `Access-Control-Allow-Origin`, con lo que el navegador descarta la respuesta.
 */

export type CorsPolicy = Readonly<{
  allowedHeaders: readonly string[]
  allowedMethods: readonly string[]
  allowedOrigins: readonly string[]
  maxAgeSeconds?: number
}>

export type Cors = Readonly<{
  /** Responde el preflight cuando la request es OPTIONS. */
  preflight: (request: Request) => Response | undefined
  /** Agrega los encabezados CORS a una respuesta ya construida. */
  decorate: (headers: Headers, request: Request) => void
}>

function isExactOrigin(value: string): boolean {
  if (value.includes("*")) return false
  try {
    const url = new URL(value)
    return (
      (url.protocol === "https:" || url.protocol === "http:") &&
      url.hostname.length > 0 &&
      value === url.origin
    )
  } catch {
    return false
  }
}

function assertPolicy(policy: CorsPolicy): void {
  if (policy.allowedOrigins.length === 0) {
    throw new Error("CORS requires at least one allowed origin")
  }
  const invalid = policy.allowedOrigins.filter(
    (origin) => !isExactOrigin(origin)
  )
  if (invalid.length > 0) {
    throw new Error(`CORS rejects non-exact origins: ${invalid.join(", ")}`)
  }
  if (policy.allowedMethods.length === 0) {
    throw new Error("CORS requires at least one allowed method")
  }
}

export function createCors(policy: CorsPolicy): Cors {
  assertPolicy(policy)
  const allowed = new Set(policy.allowedOrigins)

  // El origen viaja en un encabezado, así que la respuesta depende de él y
  // tiene que declararlo en `Vary` o una cache puede servirle a un origen la
  // respuesta que se armó para otro.
  const declareVariance = (headers: Headers) => {
    headers.append("Vary", "Origin")
  }

  const allowedOrigin = (request: Request): string | undefined => {
    const origin = request.headers.get("origin")
    // "null" es el origen opaco de un sandbox o un `file://`: nunca se permite.
    if (!origin || origin === "null") return undefined
    return allowed.has(origin) ? origin : undefined
  }

  return {
    decorate(headers, request) {
      declareVariance(headers)
      const origin = allowedOrigin(request)
      if (origin) headers.set("Access-Control-Allow-Origin", origin)
    },

    preflight(request) {
      if (request.method !== "OPTIONS") return undefined

      const headers = new Headers()
      declareVariance(headers)
      const origin = allowedOrigin(request)
      if (!origin) return new Response(null, { headers, status: 403 })

      headers.set("Access-Control-Allow-Origin", origin)
      headers.set(
        "Access-Control-Allow-Methods",
        policy.allowedMethods.join(", ")
      )
      headers.set(
        "Access-Control-Allow-Headers",
        policy.allowedHeaders.join(", ")
      )
      headers.set("Access-Control-Max-Age", String(policy.maxAgeSeconds ?? 600))
      // La API se autentica con bearer, no con cookies: no se habilitan
      // credenciales para que un origen permitido no arrastre sesión ajena.
      return new Response(null, { headers, status: 204 })
    },
  }
}
