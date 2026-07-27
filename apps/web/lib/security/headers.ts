export type Environment = "development" | "production" | "test"

export type SecurityHeader = Readonly<{ key: string; value: string }>

/**
 * Base del sitio público. No lleva CSP: una CSP con nonce obligaría a
 * renderizar cada página por request, y el marketing se sirve estático desde
 * la CDN. Poner `unsafe-inline` para simular protección sería peor que no
 * tenerla, así que la CSP de `web` queda como bloqueante declarado en
 * `docs/PRODUCTION_READINESS.md`.
 */
export function webSecurityHeaders(environment: Environment): SecurityHeader[] {
  const headers: SecurityHeader[] = [
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    {
      key: "Permissions-Policy",
      value: "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
    },
  ]

  if (environment === "production") {
    headers.unshift({
      key: "Strict-Transport-Security",
      value: "max-age=63072000; includeSubDomains; preload",
    })
  }

  return headers
}
