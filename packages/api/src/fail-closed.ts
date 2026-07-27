import { tryWriteAudit, type AuditSink } from "./audit.js"
import { errorResponse } from "./errors.js"

export type FailureContext = Readonly<{
  action: string
  audit: AuditSink
  requestId: string
}>

export type Failure = Readonly<{
  actorId?: string | null
  code: string
  decision: "deny" | "error" | "rate_limited"
  resourceId?: string | null
}>

export type ActionFailure = Readonly<{
  error: { code: string }
  ok: false
  requestId: string
}>

/**
 * Registra el rechazo. Devuelve `false` cuando no se pudo auditar: en ese caso
 * el entrypoint responde `audit_unavailable` en vez del motivo real, porque un
 * rechazo sin rastro es peor que un rechazo opaco.
 */
export async function auditFailure(
  context: FailureContext,
  failure: Failure
): Promise<boolean> {
  return tryWriteAudit(context.audit, {
    action: context.action,
    actorId: failure.actorId ?? null,
    code: failure.code,
    decision: failure.decision,
    requestId: context.requestId,
    resourceId: failure.resourceId ?? null,
  })
}

/** Registra la autorización concedida antes de ejecutar el handler. */
export async function auditAllowed(
  context: FailureContext,
  scope: Readonly<{ actorId?: string | null; resourceId?: string | null }>
): Promise<boolean> {
  return tryWriteAudit(context.audit, {
    action: context.action,
    actorId: scope.actorId ?? null,
    code: "ok",
    decision: "allow",
    requestId: context.requestId,
    resourceId: scope.resourceId ?? null,
  })
}

export function actionFailure(code: string, requestId: string): ActionFailure {
  return { error: { code }, ok: false as const, requestId }
}

/** Falla cerrado devolviendo una `Response` HTTP. */
export function createResponseFailure(context: FailureContext) {
  return async function fail(
    failure: Failure & { headers?: HeadersInit; status: number }
  ): Promise<Response> {
    if (!(await auditFailure(context, failure))) {
      return errorResponse(503, "audit_unavailable", context.requestId)
    }
    return errorResponse(
      failure.status,
      failure.code,
      context.requestId,
      failure.headers
    )
  }
}

/** Falla cerrado devolviendo el resultado serializable de una Server Action. */
export function createActionFailure(context: FailureContext) {
  return async function fail(failure: Failure): Promise<ActionFailure> {
    if (!(await auditFailure(context, failure))) {
      return actionFailure("audit_unavailable", context.requestId)
    }
    return actionFailure(failure.code, context.requestId)
  }
}
