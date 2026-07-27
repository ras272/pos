import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

const ignoredDirectories = new Set([
  ".git",
  ".next",
  ".turbo",
  "coverage",
  "dist",
  "node_modules",
  "out",
])

const patterns = [
  {
    rule: "legacy service role",
    expression: new RegExp(["service", "role"].join("_"), "i"),
  },
  {
    rule: "Supabase secret key",
    expression: new RegExp(["sb", "secret"].join("_") + "_[A-Za-z0-9_-]+", "i"),
  },
  {
    rule: "database URL",
    expression: new RegExp("postgres(?:ql)?" + ":\\/\\/[^\\s'\\\"]+", "i"),
  },
  {
    rule: "Vercel token",
    expression:
      /(?:VERCEL_(?:ACCESS_)?TOKEN|TURBO_TOKEN)\s*[:=]\s*["']?(?!<|\$\{|example|replace|your-)[^\s"']{16,}/i,
  },
  {
    rule: "Vercel token",
    expression: new RegExp("vercel" + "_[A-Za-z0-9_-]{20,}", "i"),
  },
  {
    rule: "certificate or private key material",
    expression: new RegExp(
      "-----BEGIN (?:RSA |EC |OPENSSH )?(?:PRIVATE KEY|CERTIFICATE|PKCS12)-----",
      "i"
    ),
  },
]

function normalize(filePath) {
  return filePath.replaceAll("\\", "/")
}

function isExampleOrTest(filePath) {
  const normalized = normalize(filePath).toLowerCase()
  const name = path.posix.basename(normalized)

  return (
    normalized.startsWith("docs/") ||
    normalized.includes("/__tests__/") ||
    normalized.includes("/fixtures/") ||
    /\.(?:test|spec)\.[cm]?[jt]sx?$/.test(normalized) ||
    name.endsWith(".example") ||
    name.startsWith("example.") ||
    name.includes(".example.")
  )
}

export function findSecurityPatterns({ filePath, content }) {
  if (isExampleOrTest(filePath)) return []

  const findings = []
  for (const { rule, expression } of patterns) {
    const match = expression.exec(content)
    if (!match) continue
    findings.push({
      filePath: normalize(filePath),
      line: content.slice(0, match.index).split(/\r?\n/).length,
      rule,
    })
  }
  return findings
}

async function repositoryFiles(root, directory = root) {
  const files = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (ignoredDirectories.has(entry.name)) continue
    const absolutePath = path.join(directory, entry.name)
    if (entry.isDirectory())
      files.push(...(await repositoryFiles(root, absolutePath)))
    else if (entry.isFile()) files.push(absolutePath)
  }
  return files
}

export async function scanRepository(root = process.cwd()) {
  const findings = []
  for (const absolutePath of await repositoryFiles(root)) {
    const relativePath = normalize(path.relative(root, absolutePath))
    if (
      relativePath === "scripts/security-patterns.mjs" ||
      isExampleOrTest(relativePath)
    )
      continue

    let content
    try {
      content = await readFile(absolutePath, "utf8")
    } catch {
      continue
    }
    if (content.includes("\0")) continue
    findings.push(...findSecurityPatterns({ filePath: relativePath, content }))
  }
  return findings
}

async function main() {
  const findings = await scanRepository()
  if (findings.length === 0) {
    console.log("Security pattern check passed.")
    return
  }
  for (const finding of findings) {
    console.error(
      `${finding.filePath}:${finding.line}: forbidden ${finding.rule}`
    )
  }
  process.exitCode = 1
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  await main()
}
