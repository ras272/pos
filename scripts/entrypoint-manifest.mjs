import { readFile } from "node:fs/promises"
import path from "node:path"

import { isValidIsoDate } from "./iso-date.mjs"

const httpMethods = new Set([
  "DELETE",
  "GET",
  "HEAD",
  "OPTIONS",
  "PATCH",
  "POST",
  "PUT",
])

function validateEntry(entry, index, today, seen, errors) {
  const label = `security/public-entrypoints.json[${index}]`
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    errors.push(`${label}: entry must be an object`)
    return
  }
  const key = `${entry.method} ${entry.path}`
  if (!httpMethods.has(entry.method))
    errors.push(`${label}: method must be a supported uppercase HTTP verb`)
  if (typeof entry.path !== "string" || !entry.path.startsWith("/"))
    errors.push(`${label}: path must start with /`)
  for (const field of ["reason", "owner"]) {
    if (typeof entry[field] !== "string" || !entry[field].trim())
      errors.push(`${label}: ${field} is required`)
  }
  if (!isValidIsoDate(entry.expiresOn))
    errors.push(`${label}: expiresOn must be an ISO date`)
  else if (entry.expiresOn < today)
    errors.push(`${label}: expiresOn is expired`)
  if (entry.noTenantData !== true)
    errors.push(`${label}: noTenantData must be true`)
  if (typeof entry.noMutation !== "boolean")
    errors.push(`${label}: noMutation must be a boolean`)
  if (
    entry.noMutation === false &&
    (typeof entry.mutationJustification !== "string" ||
      !entry.mutationJustification.trim())
  ) {
    errors.push(
      `${label}: mutationJustification is required when noMutation is false`
    )
  }
  if (seen.has(key)) errors.push(`${label}: duplicate public entrypoint ${key}`)
  seen.add(key)
}

export async function readPublicManifest(root, today, errors) {
  let entries
  try {
    entries = JSON.parse(
      await readFile(
        path.join(root, "security/public-entrypoints.json"),
        "utf8"
      )
    )
    if (!Array.isArray(entries)) throw new Error("root value must be an array")
  } catch (error) {
    errors.push(
      `security/public-entrypoints.json: ${error?.code === "ENOENT" ? "file is required" : error.message}`
    )
    return []
  }

  const seen = new Set()
  entries.forEach((entry, index) =>
    validateEntry(entry, index, today, seen, errors)
  )
  return entries
}
