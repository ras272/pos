import type { AuditSink } from "@workspace/api"

export type VercelAuditOptions = Readonly<{
  emit?: (line: string) => void
  source?: string
}>

/**
 * Sink de auditoría estructurado sobre la salida estándar, que es lo que Vercel
 * recolecta. Serializa exactamente los campos conocidos del evento: cualquier
 * cosa que llegue de más no se escribe, para que un token o un payload no
 * termine en los logs.
 */
export function createVercelAudit(options: VercelAuditOptions = {}): AuditSink {
  const emit =
    options.emit ??
    ((line: string) => {
      process.stdout.write(`${line}\n`)
    })

  return {
    async write(event) {
      emit(
        JSON.stringify({
          action: event.action,
          actorId: event.actorId,
          code: event.code,
          decision: event.decision,
          requestId: event.requestId,
          resourceId: event.resourceId,
          source: options.source ?? "api",
          type: "audit",
        })
      )
    },
  }
}
