import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

async function workflowFiles(root) {
  const directory = path.join(root, ".github/workflows")
  try {
    return (await readdir(directory))
      .filter((name) => /\.ya?ml$/i.test(name))
      .map((name) => path.join(directory, name))
  } catch (error) {
    if (error?.code === "ENOENT") return []
    throw error
  }
}

function runScripts(content) {
  const lines = content.split(/\r?\n/)
  const scripts = []

  for (let index = 0; index < lines.length; index += 1) {
    const match = /^(\s*)(?:-\s+)?run:\s*(.*)$/.exec(lines[index])
    if (!match) continue

    const indentation = match[1].length
    const value = match[2]
    if (!/^[>|][+-]?\s*(?:#.*)?$/.test(value)) {
      scripts.push(value)
      continue
    }

    const block = []
    while (index + 1 < lines.length) {
      const nextLine = lines[index + 1]
      const nextIndentation = /^\s*/.exec(nextLine)[0].length
      if (nextLine.trim() && nextIndentation <= indentation) break
      block.push(nextLine)
      index += 1
    }
    scripts.push(block.join("\n"))
  }

  return scripts
}

function inspectWorkflow(relativePath, content) {
  const errors = []
  if (/\bpull_request_target\b/m.test(content))
    errors.push(`${relativePath}: pull_request_target is forbidden`)
  if (/runs-on:\s*(?:\[[^\]]*\bself-hosted\b|self-hosted\b)/i.test(content))
    errors.push(`${relativePath}: self-hosted runners are forbidden`)
  if (
    /^permissions:\s*write-all(?:\s+#.*)?$/m.test(content) ||
    /^\s+["']?[a-z-]+["']?:\s*write(?:\s+#.*)?$/m.test(content)
  ) {
    errors.push(`${relativePath}: workflow permissions must remain read-only`)
  }
  if (
    !/^permissions:\s*(?:\{\s*contents:\s*read\s*\}|\r?\n\s+contents:\s+read(?:\s+#.*)?$)/m.test(
      content
    )
  ) {
    errors.push(
      `${relativePath}: top-level permissions must set contents: read`
    )
  }

  for (const match of content.matchAll(/^\s*-?\s*uses:\s*([^\s#]+).*$/gm)) {
    const reference = match[1]
    if (reference.startsWith("./")) continue
    if (reference.startsWith("docker://")) {
      if (!/@sha256:[a-f0-9]{64}$/i.test(reference))
        errors.push(
          `${relativePath}: ${reference} must pin an immutable image digest`
        )
      continue
    }
    if (!/@[a-f0-9]{40}$/i.test(reference))
      errors.push(
        `${relativePath}: ${reference} must pin an immutable 40-character SHA`
      )
  }

  if (/\$\{\{\s*secrets\./i.test(content))
    errors.push(`${relativePath}: workflow secret contexts are forbidden`)

  const scripts = runScripts(content)
  if (
    scripts.some((script) =>
      /\$\{\{[\s\S]*?github\.(?:event|actor|ref|head_ref|base_ref)\b[\s\S]*?\}\}/i.test(
        script
      )
    )
  ) {
    errors.push(
      `${relativePath}: untrusted event data cannot be interpolated into run scripts`
    )
  }
  return errors
}

export async function checkWorkflows(root = process.cwd()) {
  const errors = []
  for (const absolutePath of await workflowFiles(root)) {
    const relativePath = path.relative(root, absolutePath).replaceAll("\\", "/")
    errors.push(
      ...inspectWorkflow(relativePath, await readFile(absolutePath, "utf8"))
    )
  }
  return errors
}

async function main() {
  const files = await workflowFiles(process.cwd())
  const errors = await checkWorkflows()
  if (errors.length > 0) {
    errors.forEach((error) => console.error(error))
    process.exitCode = 1
  } else if (files.length === 0) {
    console.log(
      "No workflows exist yet; workflow enforcement activates when Task 11 adds them."
    )
  } else console.log("Workflow security check passed.")
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
)
  await main()
