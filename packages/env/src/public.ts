import { z } from "zod"

const privilegedRole = ["service", "role"].join("_")
const secretKeyPrefix = ["sb", "secret", ""].join("_")
const publishableKeyPattern = /^sb_publishable_[A-Za-z0-9_-]+$/
const jwtPattern = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/
const serverOnlyNameParts = [
  "AUTHORIZATION",
  "COOKIE",
  "DATABASE",
  "JWT",
  "PRIVATE",
  "SECRET",
  ["SERVICE", "ROLE"].join("_"),
  "TOKEN",
]

const publicEnvSchema = z
  .object({
    SUPABASE_PUBLISHABLE_KEY: z.string().regex(publishableKeyPattern),
    SUPABASE_URL: z.string().refine(isHttpUrl),
  })
  .strict()

export type PublicEnv = Readonly<{
  supabasePublishableKey: string
  supabaseUrl: string
}>

export class PublicEnvValidationError extends Error {
  override name = "PublicEnvValidationError"

  constructor(detail: string) {
    super(`Invalid public environment: ${detail}`)
  }
}

export function parsePublicEnv(input: unknown): PublicEnv {
  if (!isPlainRecord(input)) {
    throw new PublicEnvValidationError("an injected plain record is required")
  }
  if (Object.keys(input).some(isServerOnlyName)) {
    throw new PublicEnvValidationError("server-only fields are forbidden")
  }
  if (Object.values(input).some(isServerOnlyValue)) {
    throw new PublicEnvValidationError("server-only values are forbidden")
  }

  const result = publicEnvSchema.safeParse(input)
  if (!result.success) throw validationError(input, result.error)

  return Object.freeze({
    supabasePublishableKey: result.data.SUPABASE_PUBLISHABLE_KEY,
    supabaseUrl: result.data.SUPABASE_URL,
  })
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isHttpUrl(value: string): boolean {
  try {
    const url = new URL(value)
    return (
      (url.protocol === "http:" || url.protocol === "https:") &&
      url.hostname.length > 0
    )
  } catch {
    return false
  }
}

function isServerOnlyName(name: string): boolean {
  const upperName = name.toUpperCase()
  return serverOnlyNameParts.some((part) => upperName.includes(part))
}

function isServerOnlyValue(value: unknown): boolean {
  if (typeof value !== "string") return false
  return (
    value === privilegedRole ||
    value.startsWith(secretKeyPrefix) ||
    jwtPattern.test(value) ||
    /^postgres(?:ql)?:\/\//i.test(value) ||
    value.includes("-----BEGIN")
  )
}

function validationError(
  input: Record<string, unknown>,
  error: z.ZodError
): PublicEnvValidationError {
  if (error.issues.some((issue) => issue.code === "unrecognized_keys")) {
    return new PublicEnvValidationError("unexpected fields are forbidden")
  }
  if (input.SUPABASE_URL === undefined) {
    return new PublicEnvValidationError("SUPABASE_URL is required")
  }
  if (error.issues.some((issue) => issue.path[0] === "SUPABASE_URL")) {
    return new PublicEnvValidationError("SUPABASE_URL must be an HTTP(S) URL")
  }
  if (input.SUPABASE_PUBLISHABLE_KEY === undefined) {
    return new PublicEnvValidationError("SUPABASE_PUBLISHABLE_KEY is required")
  }
  return new PublicEnvValidationError(
    "SUPABASE_PUBLISHABLE_KEY must use the sb_publishable_ format"
  )
}
