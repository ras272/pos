import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"

import yaml from "js-yaml"

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

function valuesForKey(value, target, results = [], seen = new WeakSet()) {
  if (!value || typeof value !== "object" || seen.has(value)) return results
  seen.add(value)

  if (Array.isArray(value)) {
    value.forEach((item) => valuesForKey(item, target, results, seen))
    return results
  }

  for (const [key, child] of Object.entries(value)) {
    if (key === target) results.push(child)
    valuesForKey(child, target, results, seen)
  }
  return results
}

function workflowExpressions(content) {
  return [...content.matchAll(/\$\{\{([\s\S]*?)\}\}/g)].map((match) => match[1])
}

function usesUntrustedGithubContext(expression) {
  return (
    /\bgithub\s*\[/i.test(expression) ||
    /\bgithub\s*\.\s*(?:event|actor|ref|head_ref|base_ref)\b/i.test(expression)
  )
}

function hasTrigger(value, target) {
  if (typeof value === "string") return value === target
  if (Array.isArray(value)) return value.includes(target)
  return Boolean(value && typeof value === "object" && target in value)
}

function hasWritePermission(workflow) {
  return valuesForKey(workflow, "permissions").some((permissions) => {
    if (permissions === "write-all") return true
    return Boolean(
      permissions &&
      typeof permissions === "object" &&
      Object.values(permissions).some((value) => value === "write")
    )
  })
}

function hasReadOnlyTopLevelPermissions(workflow) {
  const permissions = workflow?.permissions
  return Boolean(
    permissions &&
    typeof permissions === "object" &&
    !Array.isArray(permissions) &&
    permissions.contents === "read"
  )
}

function inspectActionReference(relativePath, reference, errors) {
  if (typeof reference !== "string") {
    errors.push(`${relativePath}: workflow uses values must be strings`)
    return
  }
  if (reference.startsWith("./")) return
  if (reference.startsWith("docker://")) {
    if (!/@sha256:[a-f0-9]{64}$/i.test(reference))
      errors.push(
        `${relativePath}: ${reference} must pin an immutable image digest`
      )
    return
  }
  if (!/@[a-f0-9]{40}$/i.test(reference))
    errors.push(
      `${relativePath}: ${reference} must pin an immutable 40-character SHA`
    )
}

function inspectWorkflow(relativePath, content) {
  const errors = []
  let workflow
  try {
    workflow = yaml.load(content)
    if (!workflow || typeof workflow !== "object" || Array.isArray(workflow))
      throw new Error("root value must be an object")
  } catch (error) {
    return [`${relativePath}: invalid workflow YAML: ${error.message}`]
  }

  if (hasTrigger(workflow.on, "pull_request_target"))
    errors.push(`${relativePath}: pull_request_target is forbidden`)

  const runners = valuesForKey(workflow, "runs-on").flat()
  if (runners.some((runner) => runner === "self-hosted"))
    errors.push(`${relativePath}: self-hosted runners are forbidden`)
  if (
    runners.some(
      (runner) =>
        typeof runner !== "string" || workflowExpressions(runner).length > 0
    )
  )
    errors.push(`${relativePath}: dynamic runs-on values are forbidden`)

  if (hasWritePermission(workflow))
    errors.push(`${relativePath}: workflow permissions must remain read-only`)
  if (!hasReadOnlyTopLevelPermissions(workflow))
    errors.push(
      `${relativePath}: top-level permissions must set contents: read`
    )

  valuesForKey(workflow, "uses").forEach((reference) =>
    inspectActionReference(relativePath, reference, errors)
  )

  const expressions = workflowExpressions(content)
  if (expressions.some((expression) => /\bsecrets\b/i.test(expression)))
    errors.push(`${relativePath}: workflow secret contexts are forbidden`)

  if (expressions.some(usesUntrustedGithubContext)) {
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
