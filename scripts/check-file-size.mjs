import { createHash } from "node:crypto"
import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

import { isValidIsoDate } from "./iso-date.mjs"

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
const sourceExtensions = new Set([".js", ".jsx", ".mjs", ".ts", ".tsx"])

function normalize(filePath) {
  return filePath.replaceAll("\\", "/")
}

function isExcluded(filePath, generatedFiles) {
  return (
    filePath === "packages/database/src/database.types.ts" ||
    generatedFiles.has(filePath) ||
    filePath.startsWith("docs/") ||
    filePath.startsWith("supabase/migrations/") ||
    filePath.includes("/__tests__/") ||
    /\.(?:test|spec)(?:-d)?\.[cm]?[jt]sx?$/.test(filePath)
  )
}

async function readGeneratedFiles(root, errors) {
  let entries
  try {
    entries = JSON.parse(
      await readFile(
        path.join(root, "security/generated-file-hashes.json"),
        "utf8"
      )
    )
  } catch (error) {
    if (error?.code === "ENOENT") return new Set()
    errors.push(`security/generated-file-hashes.json: ${error.message}`)
    return new Set()
  }
  if (!Array.isArray(entries)) {
    errors.push("security/generated-file-hashes.json: root must be an array")
    return new Set()
  }
  const generatedFiles = new Set()
  for (const [index, entry] of entries.entries()) {
    const label = `security/generated-file-hashes.json[${index}]`
    if (
      !entry ||
      typeof entry.path !== "string" ||
      !entry.path.startsWith("packages/ui/src/components/") ||
      !/^[a-f0-9]{64}$/.test(entry.sha256 ?? "")
    ) {
      errors.push(`${label}: valid component path and sha256 are required`)
      continue
    }
    try {
      const content = await readFile(path.join(root, entry.path), "utf8")
      const actual = createHash("sha256").update(content).digest("hex")
      if (actual === entry.sha256) generatedFiles.add(entry.path)
      else
        errors.push(`${label}: generated file hash changed for ${entry.path}`)
    } catch (error) {
      errors.push(`${label}: cannot read ${entry.path}: ${error.message}`)
    }
  }
  return generatedFiles
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
    if (!isValidIsoDate(entry.expiresOn))
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
  const generatedFiles = await readGeneratedFiles(root, errors)
  for (const absolutePath of await sourceFiles(root)) {
    const relativePath = normalize(path.relative(root, absolutePath))
    if (isExcluded(relativePath, generatedFiles)) continue
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
