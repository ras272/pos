import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"
import ts from "typescript"

import { readPublicManifest } from "./entrypoint-manifest.mjs"

const httpMethods = new Set([
  "DELETE",
  "GET",
  "HEAD",
  "OPTIONS",
  "PATCH",
  "POST",
  "PUT",
])
const wrappers = new Set(["defineAuthenticatedRoute", "definePublicRoute"])
const ignoredDirectories = new Set([
  ".git",
  ".next",
  ".turbo",
  "coverage",
  "dist",
  "node_modules",
  "out",
])

function normalize(filePath) {
  return filePath.replaceAll("\\", "/")
}

async function sourceFiles(root, directory = root) {
  const files = []
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (ignoredDirectories.has(entry.name)) continue
    const absolutePath = path.join(directory, entry.name)
    if (entry.isDirectory())
      files.push(...(await sourceFiles(root, absolutePath)))
    else if (entry.isFile() && /\.[jt]sx?$/.test(entry.name))
      files.push(absolutePath)
  }
  return files
}

function hasModifier(node, kind) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === kind))
}

function calledWrapper(expression) {
  return expression &&
    ts.isCallExpression(expression) &&
    ts.isIdentifier(expression.expression)
    ? expression.expression.text
    : undefined
}

function localInitializers(sourceFile) {
  const initializers = new Map()
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name))
        initializers.set(declaration.name.text, declaration.initializer)
    }
  }
  return initializers
}

function exportedValues(sourceFile) {
  const values = []
  const initializers = localInitializers(sourceFile)
  for (const statement of sourceFile.statements) {
    if (hasModifier(statement, ts.SyntaxKind.ExportKeyword)) {
      if (ts.isFunctionDeclaration(statement) && statement.name)
        values.push({ name: statement.name.text })
      if (ts.isVariableStatement(statement)) {
        for (const declaration of statement.declarationList.declarations) {
          if (ts.isIdentifier(declaration.name))
            values.push({
              name: declaration.name.text,
              initializer: declaration.initializer,
            })
        }
      }
    }
    if (
      ts.isExportDeclaration(statement) &&
      !statement.isTypeOnly &&
      statement.exportClause &&
      ts.isNamedExports(statement.exportClause)
    ) {
      for (const element of statement.exportClause.elements) {
        if (element.isTypeOnly) continue
        const localName = (element.propertyName ?? element.name).text
        values.push({
          name: element.name.text,
          initializer: statement.moduleSpecifier
            ? undefined
            : initializers.get(localName),
        })
      }
    }
    if (ts.isExportAssignment(statement) && !statement.isExportEquals)
      values.push({ name: "default", initializer: statement.expression })
  }
  return values
}

function routePath(relativePath) {
  const segments = relativePath
    .split("/")
    .slice(3, -1)
    .filter((segment) => !/^\(.*\)$/.test(segment))
  return `/${segments.join("/")}`
}

function checkRoute(relativePath, sourceFile, manifest, observed, errors) {
  const endpointPath = routePath(relativePath)
  for (const value of exportedValues(sourceFile)) {
    if (!httpMethods.has(value.name)) continue
    const wrapper = calledWrapper(value.initializer)
    if (!wrappers.has(wrapper)) {
      errors.push(
        `${relativePath}: ${value.name} must directly call defineAuthenticatedRoute or definePublicRoute`
      )
      continue
    }
    if (wrapper !== "definePublicRoute") continue
    const key = `${value.name} ${endpointPath}`
    observed.add(key)
    if (!manifest.some((entry) => `${entry.method} ${entry.path}` === key)) {
      errors.push(
        `${relativePath}: public ${value.name} ${endpointPath} is not listed`
      )
    }
  }
}

function checkServerActions(relativePath, sourceFile, errors) {
  const first = sourceFile.statements[0]
  const useServer =
    first &&
    ts.isExpressionStatement(first) &&
    ts.isStringLiteral(first.expression) &&
    first.expression.text === "use server"
  if (!useServer) return
  for (const value of exportedValues(sourceFile)) {
    if (calledWrapper(value.initializer) !== "defineAuthenticatedAction") {
      errors.push(
        `${relativePath}: ${value.name} must directly call defineAuthenticatedAction`
      )
    }
  }
}

export async function checkEntrypoints(
  root = process.cwd(),
  { now = new Date() } = {}
) {
  const errors = []
  const today = now.toISOString().slice(0, 10)
  const manifest = await readPublicManifest(root, today, errors)
  const observed = new Set()
  for (const absolutePath of await sourceFiles(root)) {
    const relativePath = normalize(path.relative(root, absolutePath))
    const content = await readFile(absolutePath, "utf8")
    const sourceFile = ts.createSourceFile(
      relativePath,
      content,
      ts.ScriptTarget.Latest,
      true,
      relativePath.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS
    )
    if (
      relativePath.startsWith("apps/api/app/") &&
      relativePath.endsWith("/route.ts")
    ) {
      checkRoute(relativePath, sourceFile, manifest, observed, errors)
    }
    checkServerActions(relativePath, sourceFile, errors)
  }
  manifest.forEach((entry, index) => {
    const key = `${entry.method} ${entry.path}`
    if (!observed.has(key))
      errors.push(
        `security/public-entrypoints.json[${index}]: ${key} does not match a definePublicRoute export`
      )
  })
  return errors
}

async function main() {
  const errors = await checkEntrypoints()
  if (errors.length === 0) console.log("Entrypoint wrapper check passed.")
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
