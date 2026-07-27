import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

const limit = 250
const ignoredDirectories = new Set([
  ".git",
  ".next",
  ".turbo",
  "coverage",
  "dist",
  "node_modules",
  "out",
])
const sourceExtensions = new Set([".mjs", ".ts", ".tsx"])

function normalize(filePath) {
  return filePath.replaceAll("\\", "/")
}

function isExcluded(filePath) {
  return (
    filePath === "packages/database/src/database.types.ts" ||
    filePath.startsWith("packages/ui/src/components/") ||
    filePath.startsWith("docs/") ||
    filePath.startsWith("supabase/migrations/") ||
    filePath.includes("/__tests__/") ||
    /\.(?:test|spec)(?:-d)?\.[cm]?[jt]sx?$/.test(filePath)
  )
}

async function sourceFiles(root, directory = root) {
  const files = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (ignoredDirectories.has(entry.name)) continue
    const absolutePath = path.join(directory, entry.name)
    if (entry.isDirectory())
      files.push(...(await sourceFiles(root, absolutePath)))
    else if (entry.isFile() && sourceExtensions.has(path.extname(entry.name)))
      files.push(absolutePath)
  }
  return files
}

async function readExceptions(root, errors) {
  try {
    const parsed = JSON.parse(
      await readFile(
        path.join(root, "security/file-size-exceptions.json"),
        "utf8"
      )
    )
    if (!Array.isArray(parsed)) throw new Error("root value must be an array")
    return parsed
  } catch (error) {
    if (error?.code === "ENOENT") return []
    errors.push(`security/file-size-exceptions.json: ${error.message}`)
    return []
  }
}

function validDate(value) {
  return (
    typeof value === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00Z`))
  )
}

function validateExceptions(exceptions, oversized, today, errors) {
  const seen = new Set()
  exceptions.forEach((entry, index) => {
    const label = `security/file-size-exceptions.json[${index}]`
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${label}: entry must be an object`)
      return
    }
    if (typeof entry.path !== "string" || !entry.path)
      errors.push(`${label}: path is required`)
    else if (seen.has(entry.path))
      errors.push(`${label}: duplicate path ${entry.path}`)
    else seen.add(entry.path)
    for (const field of ["reason", "owner"]) {
      if (typeof entry[field] !== "string" || !entry[field].trim())
        errors.push(`${label}: ${field} is required`)
    }
    if (!validDate(entry.expiresOn))
      errors.push(`${label}: expiresOn must be an ISO date`)
    else if (entry.expiresOn < today)
      errors.push(`${label}: expiresOn is expired`)
    if (typeof entry.path === "string" && !oversized.has(entry.path)) {
      errors.push(
        `${label}: ${entry.path} does not match an oversized source file`
      )
    }
  })
}

export async function checkFileSizes(
  root = process.cwd(),
  { now = new Date() } = {}
) {
  const errors = []
  const oversized = new Map()
  for (const absolutePath of await sourceFiles(root)) {
    const relativePath = normalize(path.relative(root, absolutePath))
    if (isExcluded(relativePath)) continue
    const content = await readFile(absolutePath, "utf8")
    const lines =
      content === "" ? 0 : content.replace(/\r?\n$/, "").split(/\r?\n/).length
    if (lines > limit) oversized.set(relativePath, lines)
  }

  const exceptions = await readExceptions(root, errors)
  const today = now.toISOString().slice(0, 10)
  validateExceptions(exceptions, oversized, today, errors)
  const exceptedPaths = new Set(
    exceptions.map((entry) => entry?.path).filter(Boolean)
  )
  for (const [filePath, lines] of oversized) {
    if (!exceptedPaths.has(filePath))
      errors.push(`${filePath}: ${lines} lines exceeds the ${limit}-line limit`)
  }
  return errors
}

async function main() {
  const errors = await checkFileSizes()
  if (errors.length === 0)
    console.log(`File-size check passed (${limit}-line limit).`)
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
