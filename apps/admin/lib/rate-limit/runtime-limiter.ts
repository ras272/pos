import type { RateLimiter } from "@workspace/api"

export type RuntimeLimiterOptions = Readonly<{
  environment: "development" | "production" | "test"
  external?: RateLimiter
  now?: () => number
  requestsPerWindow?: number
  windowMs?: number
}>

/**
 * Limitador en memoria. Solo sirve en desarrollo: cada instancia serverless
 * tiene su propio proceso, así que en producción no limita nada real.
 */
export function createInMemoryLimiter(
  options: Pick<
    RuntimeLimiterOptions,
    "now" | "requestsPerWindow" | "windowMs"
  > = {}
): RateLimiter {
  const now = options.now ?? (() => Date.now())
  const windowMs = options.windowMs ?? 60_000
  const requestsPerWindow = options.requestsPerWindow ?? 60
  const windows = new Map<string, { count: number; resetAt: number }>()

  return {
    kind: "development-memory",
    async limit({ actorId, policy, resourceId }) {
      const key = `${policy}|${actorId ?? "anonymous"}|${resourceId ?? "-"}`
      const current = now()
      const window = windows.get(key)

      if (!window || window.resetAt <= current) {
        windows.set(key, { count: 1, resetAt: current + windowMs })
        return { allowed: true }
      }
      window.count += 1
      if (window.count <= requestsPerWindow) return { allowed: true }

      return {
        allowed: false,
        retryAfterSeconds: Math.ceil((window.resetAt - current) / 1000),
      }
    },
  }
}

/**
 * Adaptador de producción. Todavía no hay backend de límites elegido, así que
 * falla cerrado: cada Server Action responde con error auditado hasta que se
 * configure uno real. Es un bloqueante de `docs/PRODUCTION_READINESS.md`.
 */
export function createPlatformLimiter(backend?: RateLimiter): RateLimiter {
  return {
    kind: "external",
    async limit(input) {
      if (!backend) {
        throw new Error("No external rate-limit backend is configured")
      }
      return backend.limit(input)
    },
  }
}

export function createRuntimeLimiter(
  options: RuntimeLimiterOptions
): RateLimiter {
  if (options.environment === "production") {
    if (!options.external) {
      throw new Error(
        "Production requires an externally enforced rate limiter; the in-memory limiter does not limit across serverless instances"
      )
    }
    if (options.external.kind !== "external") {
      throw new Error("Production requires a limiter of kind 'external'")
    }
    return options.external
  }
  return options.external ?? createInMemoryLimiter(options)
}
