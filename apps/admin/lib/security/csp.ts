export type Environment = "development" | "production" | "test"

export type SecurityHeader = Readonly<{ key: string; value: string }>

export type CspOptions = Readonly<{
  /** Orígenes exactos que el backoffice puede llamar por fetch/XHR. */
  connectSrc: readonly string[]
  environment: Environment
  nonce: string
}>

export function createNonce(): string {
  return Buffer.from(crypto.randomUUID()).toString("base64")
}

function assertExactOrigin(value: string): string {
  if (value.includes("*")) {
    throw new Error(`connect-src rejects a wildcard origin: ${value}`)
  }
  let url: URL
  try {
    url = new URL(value)
  } catch {
    throw new Error(`connect-src requires an absolute origin: ${value}`)
  }
  if (
    (url.protocol !== "https:" && url.protocol !== "http:") ||
    value !== url.origin
  ) {
    throw new Error(`connect-src requires an exact origin: ${value}`)
  }
  return url.origin
}

/**
 * CSP estricta con nonce. En producción no lleva `unsafe-inline` ni
 * `unsafe-eval`: solo corre lo que trae el nonce de esta request. En
 * desarrollo React necesita `eval` para reconstruir stacks del servidor.
 */
export function contentSecurityPolicy(options: CspOptions): string {
  const isDev = options.environment === "development"
  const origins = options.connectSrc.map(assertExactOrigin)

  const directives = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${options.nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ""}`,
    `style-src 'self' ${isDev ? "'unsafe-inline'" : `'nonce-${options.nonce}'`}`,
    "img-src 'self' blob: data:",
    "font-src 'self'",
    ["connect-src 'self'", ...origins].join(" "),
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ]

  return directives.join("; ")
}

/**
 * Encabezados de endurecimiento del backoffice. HSTS solo en producción: en
 * desarrollo forzaría HTTPS sobre localhost y dejaría el navegador anclado.
 */
export function hardeningHeaders(environment: Environment): SecurityHeader[] {
  const headers: SecurityHeader[] = [
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "no-referrer" },
    {
      key: "Permissions-Policy",
      value: "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
    },
    // Una pantalla autenticada nunca se guarda en una cache compartida.
    { key: "Cache-Control", value: "private, no-store" },
  ]

  if (environment === "production") {
    headers.unshift({
      key: "Strict-Transport-Security",
      value: "max-age=63072000; includeSubDomains; preload",
    })
  }

  return headers
}
