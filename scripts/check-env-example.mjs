import { readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

import createIgnore from "ignore"

const requiredPublicVariables = [
  "ADMIN_ORIGIN",
  "CAJA_ORIGIN",
  "NEXT_PUBLIC_API_URL",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "VITE_API_URL",
  "VITE_SUPABASE_URL",
  "VITE_SUPABASE_PUBLISHABLE_KEY",
]
const forbiddenNameParts = [
  "SECRET",
  ["SERVICE", "ROLE"].join("_"),
  "DATABASE_URL",
  "VERCEL_TOKEN",
  "PRIVATE_KEY",
]
const forbiddenValuePatterns = [
  /sb_secret_/i,
  /service[_-]?role/i,
  /postgres(?:ql)?:\/\//i,
  /vercel_[a-z0-9_-]+/i,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i,
]

function parseEnvironment(content) {
  const values = new Map()
  for (const line of content.split(/\r?\n/)) {
    const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line.trim())
    if (!match) continue

    const assignments = values.get(match[1]) ?? []
    assignments.push(match[2])
    values.set(match[1], assignments)
  }
  return values
}

function isPlaceholder(value) {
  return /(?:your-|example|placeholder|replace-me|<[^>]+>)/i.test(value)
}

export async function validateEnvExample(root = process.cwd()) {
  const errors = []
  let content = ""
  try {
    content = await readFile(path.join(root, ".env.example"), "utf8")
  } catch (error) {
    errors.push(
      `.env.example: ${error?.code === "ENOENT" ? "file is required" : error.message}`
    )
  }

  const values = parseEnvironment(content)
  for (const variable of requiredPublicVariables) {
    if (!values.has(variable))
      errors.push(`.env.example: ${variable} is required`)
    else if (!values.get(variable).every(isPlaceholder))
      errors.push(`.env.example: ${variable} must contain a placeholder`)
  }
  for (const [variable, assignments] of values) {
    if (assignments.length > 1)
      errors.push(
        `.env.example: ${variable} must not be declared more than once`
      )
    if (
      !requiredPublicVariables.includes(variable) ||
      forbiddenNameParts.some((part) => variable.includes(part))
    ) {
      errors.push(
        `.env.example: ${variable} is not an approved public variable`
      )
    }
    if (
      assignments.some((value) =>
        forbiddenValuePatterns.some((pattern) => pattern.test(value))
      )
    )
      errors.push(`.env.example: ${variable} contains a forbidden secret value`)
  }

  try {
    const gitignore = await readFile(path.join(root, ".gitignore"), "utf8")
    if (!/^\.env\*\s*$/m.test(gitignore))
      errors.push(".gitignore: .env* must remain ignored")
    if (!/^!\.env\.example\s*$/m.test(gitignore))
      errors.push(".gitignore: !.env.example exception is required")
    else if (createIgnore().add(gitignore).ignores(".env.example"))
      errors.push(
        ".gitignore: .env.example must remain unignored after all rules"
      )
  } catch (error) {
    errors.push(
      `.gitignore: ${error?.code === "ENOENT" ? "file is required" : error.message}`
    )
  }
  return errors
}

async function main() {
  const errors = await validateEnvExample()
  if (errors.length === 0) console.log("Environment example check passed.")
  else {
    errors.forEach((error) => console.error(error))
    process.exitCode = 1
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
)
  await main()
