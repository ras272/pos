export type AuditEvent = Readonly<{
  action: string
  actorId: string | null
  code: string
  decision: "allow" | "deny" | "error" | "rate_limited"
  requestId: string
  resourceId: string | null
}>

export type AuditSink = { write: (event: AuditEvent) => Promise<void> }

export function isAuditSink(value: unknown): value is AuditSink {
  return (
    typeof value === "object" &&
    value !== null &&
    "write" in value &&
    typeof value.write === "function"
  )
}

const sensitiveValue =
  /authorization|bearer\s|cookie|password|payload|secret|token|eyJ[A-Za-z0-9_-]+\./i

function redact(value: string | null | undefined): string | null {
  if (!value || sensitiveValue.test(value)) return value ? "[redacted]" : null
  return value
}

export async function writeAudit(
  sink: AuditSink,
  event: AuditEvent
): Promise<void> {
  await sink.write({
    action: redact(event.action) ?? "[redacted]",
    actorId: redact(event.actorId),
    code: event.code,
    decision: event.decision,
    requestId: event.requestId,
    resourceId: redact(event.resourceId),
  })
}

export async function tryWriteAudit(
  sink: unknown,
  event: AuditEvent
): Promise<boolean> {
  if (!isAuditSink(sink)) return false
  try {
    await writeAudit(sink, event)
    return true
  } catch {
    return false
  }
}
