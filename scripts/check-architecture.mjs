import { builtinModules } from "node:module"
import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { pathToFileURL } from "node:url"
import ts from "typescript"

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
const nodeModules = new Set(
  builtinModules.flatMap((name) => [name, `node:${name}`])
)
const browserSafeExternalImports = new Set([
  "@supabase/supabase-js",
  "@vitejs/plugin-react",
  "react",
  "react-dom",
  "react-dom/client",
  "react/jsx-runtime",
  "vite",
  "vitest",
  "zod",
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
    else if (entry.isFile() && sourceExtensions.has(path.extname(entry.name)))
      files.push(absolutePath)
  }
  return files
}

function moduleReferences(sourceFile) {
  const references = []
  const visit = (node) => {
    if (
      (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) &&
      node.moduleSpecifier &&
      ts.isStringLiteral(node.moduleSpecifier)
    ) {
      const typeOnly = ts.isImportDeclaration(node)
        ? Boolean(
            node.importClause?.isTypeOnly ||
            node.importClause?.namedBindings?.elements?.every(
              (item) => item.isTypeOnly
            )
          )
        : Boolean(node.isTypeOnly)
      references.push({ specifier: node.moduleSpecifier.text, typeOnly })
    }
    if (
      ts.isCallExpression(node) &&
      (node.expression.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(node.expression) &&
          node.expression.text === "require"))
    ) {
      const [argument] = node.arguments
      if (argument && ts.isStringLiteral(argument))
        references.push({ specifier: argument.text, typeOnly: false })
    }
    ts.forEachChild(node, visit)
  }
  visit(sourceFile)
  return references
}

function isBrowserSafeWorkspaceImport(specifier, typeOnly) {
  if (typeOnly) return true
  return (
    specifier === "@workspace/database" ||
    specifier === "@workspace/env/public" ||
    specifier === "@workspace/supabase/browser" ||
    specifier === "@workspace/ui/globals.css" ||
    /^@workspace\/ui\/(?:components|hooks|lib)\//.test(specifier)
  )
}

function isExternalImport(specifier) {
  return !specifier.startsWith(".") && !specifier.startsWith("/")
}

function isCajaToolingConfig(relativePath) {
  return /^apps\/caja\/[^/]+\.config\.[cm]?[jt]sx?$/.test(relativePath)
}

function packageImportsApp(root, absolutePath, specifier) {
  if (specifier.startsWith(".")) {
    return normalize(
      path.relative(root, path.resolve(path.dirname(absolutePath), specifier))
    ).startsWith("apps/")
  }
  return specifier === "apps" || specifier.startsWith("apps/")
}

export async function checkArchitecture(root = process.cwd()) {
  const errors = []
  for (const absolutePath of await sourceFiles(root)) {
    const relativePath = normalize(path.relative(root, absolutePath))
    if (
      /^(?:route\.ts|route\.js)$/.test(path.posix.basename(relativePath)) &&
      relativePath.startsWith("apps/") &&
      !relativePath.startsWith("apps/api/")
    ) {
      errors.push(
        `${relativePath}: Route Handlers are allowed only in apps/api`
      )
    }

    const content = await readFile(absolutePath, "utf8")
    const sourceFile = ts.createSourceFile(
      relativePath,
      content,
      ts.ScriptTarget.Latest,
      true,
      relativePath.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS
    )
    for (const { specifier, typeOnly } of moduleReferences(sourceFile)) {
      if (
        relativePath.startsWith("packages/") &&
        packageImportsApp(root, absolutePath, specifier)
      ) {
        errors.push(`${relativePath}: packages cannot import from apps`)
      }
      if (
        !relativePath.startsWith("apps/caja/") ||
        isCajaToolingConfig(relativePath)
      )
        continue
      const forbidden =
        nodeModules.has(specifier) ||
        specifier === "server-only" ||
        specifier === "next" ||
        specifier.startsWith("next/") ||
        (specifier.startsWith("@workspace/") &&
          !isBrowserSafeWorkspaceImport(specifier, typeOnly)) ||
        (!typeOnly &&
          isExternalImport(specifier) &&
          !specifier.startsWith("@workspace/") &&
          !browserSafeExternalImports.has(specifier))
      if (forbidden)
        errors.push(`${relativePath}: caja cannot import ${specifier}`)
    }
  }
  return errors
}

async function main() {
  const errors = await checkArchitecture()
  if (errors.length === 0) console.log("Architecture boundary check passed.")
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
