export type Environment = "development" | "production" | "test"

export type SecurityHeader = Readonly<{ key: string; value: string }>

/**
 * La API solo devuelve JSON: no ejecuta scripts, no se embebe y no se cachea.
 * La CSP acá no protege un documento, cierra el caso de que un navegador
 * decida renderizar una respuesta como si lo fuera.
 */
export function apiSecurityHeaders(environment: Environment): SecurityHeader[] {
  const headers: SecurityHeader[] = [
    {
      key: "Content-Security-Policy",
      value: "default-src 'none'; frame-ancestors 'none'",
    },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "no-referrer" },
    {
      key: "Permissions-Policy",
      value: "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
    },
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
