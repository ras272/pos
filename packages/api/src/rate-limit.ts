export type RateLimitInput = Readonly<{
  action: string
  actorId: string | null
  policy: string
  resourceId: string | null
}>

export type RateLimiter = {
  kind: "development-memory" | "external"
  limit: (
    input: RateLimitInput
  ) => Promise<{ allowed: boolean; retryAfterSeconds?: number }>
}

export function isExecutableRateLimiter(value: unknown): value is RateLimiter {
  return (
    typeof value === "object" &&
    value !== null &&
    "limit" in value &&
    typeof value.limit === "function"
  )
}

export function assertProductionRateLimiter(
  environment: "development" | "production" | "test" | undefined,
  limiter: RateLimiter
): void {
  if (
    limiter.kind === "development-memory" &&
    environment !== "development" &&
    environment !== "test"
  ) {
    throw new Error(
      "The in-memory limiter is allowed only in development or test"
    )
  }
}

export function assertNamedRateLimitPolicy(policy: string): void {
  if (!policy.trim()) throw new Error("A named rate-limit policy is required")
}
