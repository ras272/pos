import { spawnSync } from "node:child_process"
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const generatedTypesPath = join(
  rootDir,
  "packages",
  "database",
  "src",
  "database.types.ts"
)
const supabasePgdeltaPath = join(rootDir, "supabase", ".temp", "pgdelta")
const supabaseCliPath = join(
  rootDir,
  "node_modules",
  "supabase",
  "dist",
  "supabase.js"
)

let tempDir

function fail(message) {
  throw new Error(`[db:types:check] ${message}`)
}

function runSupabase(args, options = {}) {
  const result = spawnSync(process.execPath, [supabaseCliPath, ...args], {
    cwd: rootDir,
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
  })

  if (result.error) {
    fail(`Could not run "supabase ${args.join(" ")}": ${result.error.message}`)
  }

  if (result.status !== 0) {
    const details = options.capture ? result.stderr.toString("utf8").trim() : ""
    fail(`Failed "supabase ${args.join(" ")}"${details ? `:\n${details}` : ""}`)
  }

  return result.stdout
}

function firstDifference(left, right) {
  const max = Math.min(left.length, right.length)

  for (let index = 0; index < max; index += 1) {
    if (left[index] !== right[index]) {
      return index
    }
  }

  return left.length === right.length ? -1 : max
}

try {
  console.log("[db:types:check] Resetting local Supabase...")
  runSupabase(["db", "reset", "--local"])

  tempDir = await mkdtemp(join(tmpdir(), "gestion-gastr-db-types-"))
  const tempTypesPath = join(tempDir, "database.types.ts")

  console.log("[db:types:check] Regenerating types to a temporary file...")
  const generatedTypes = runSupabase(
    ["gen", "types", "--local", "--schema", "public"],
    { capture: true }
  )
  await writeFile(tempTypesPath, generatedTypes)

  const [committedTypes, freshTypes] = await Promise.all([
    readFile(generatedTypesPath),
    readFile(tempTypesPath),
  ])

  if (!committedTypes.equals(freshTypes)) {
    const byteOffset = firstDifference(committedTypes, freshTypes)

    fail(
      [
        "Generated database types have drift.",
        `Committed file: ${generatedTypesPath} (${committedTypes.length} bytes)`,
        `Temporary file: ${tempTypesPath} (${freshTypes.length} bytes)`,
        `First differing byte: ${byteOffset}`,
        "Run pnpm db:types and review the diff before committing.",
      ].join("\n")
    )
  }

  console.log("[db:types:check] Generated database types are up to date.")
} finally {
  if (tempDir) {
    await rm(tempDir, { force: true, recursive: true })
  }

  await rm(supabasePgdeltaPath, { force: true, recursive: true })
}
