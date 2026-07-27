import { defineAuthenticatedRoute } from "@workspace/api"
import { z } from "zod"

import { routeSecurity } from "../../../lib/http/secure-route"

const schema = z.object({ subject: z.string().min(1) }).strict()

/**
 * Route de contrato: no tiene valor de negocio, existe para probar que ningÃºn
 * handler puede ejecutarse si falla la identidad, la autorizaciÃ³n, la
 * validaciÃ³n, el cliente con alcance, el limitador o la auditorÃ­a.
 */
export const POST = defineAuthenticatedRoute({
  ...routeSecurity(),
  action: "security.contract",
  // El actor solo puede preguntar por sÃ­ mismo. Cualquier otro sujeto es 403.
  authorize: async (input, actor) => ({ allowed: input.subject === actor.id }),
  handler: async ({ actor }) => ({ subject: actor.id }),
  rateLimitPolicy: "security.contract",
  resourceId: (input) => input.subject,
  schema,
  toDto: (output: { subject: string }) => ({
    contract: "authenticated" as const,
    subject: output.subject,
  }),
})
