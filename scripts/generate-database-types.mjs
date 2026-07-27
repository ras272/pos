import { spawnSync } from "node:child_process"
import { writeFile } from "node:fs/promises"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const outputPath =
  process.argv[2] ??
  join(rootDir, "packages", "database", "src", "database.types.ts")
const supabaseCliPath = join(
  rootDir,
  "node_modules",
  "supabase",
  "dist",
  "supabase.js"
)
const supabaseArgs = [
  supabaseCliPath,
  "gen",
  "types",
  "--local",
  "--schema",
  "public",
]

const result = spawnSync(process.execPath, supabaseArgs, {
  cwd: rootDir,
  stdio: ["ignore", "pipe", "inherit"],
})

if (result.error) {
  throw new Error(
    `No se pudo generar tipos de Supabase: ${result.error.message}`
  )
}

if (result.status !== 0) {
  process.exit(result.status ?? 1)
}

await writeFile(outputPath, result.stdout)
