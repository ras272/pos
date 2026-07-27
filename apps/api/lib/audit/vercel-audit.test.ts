import { describe, expect, it } from "vitest"

import { createVercelAudit } from "./vercel-audit"

const event = {
  action: "security.contract",
  actorId: "actor-1",
  code: "ok",
  decision: "allow" as const,
  requestId: "req-1",
  resourceId: "actor-1",
}

describe("createVercelAudit", () => {
  it("emits one structured JSON line per event", async () => {
    const lines: string[] = []
    const audit = createVercelAudit({ emit: (line) => lines.push(line) })

    await audit.write(event)

    expect(lines).toHaveLength(1)
    expect(JSON.parse(lines[0]!)).toEqual({
      action: "security.contract",
      actorId: "actor-1",
      code: "ok",
      decision: "allow",
      requestId: "req-1",
      resourceId: "actor-1",
      source: "api",
      type: "audit",
    })
  })

  it("writes only the known fields, so nothing extra reaches the logs", async () => {
    const lines: string[] = []
    const audit = createVercelAudit({ emit: (line) => lines.push(line) })

    await audit.write({
      ...event,
      accessToken: "no-debe-loguearse",
      payload: { pan: "4111111111111111" },
    } as never)

    expect(lines[0]).not.toContain("no-debe-loguearse")
    expect(lines[0]).not.toContain("4111111111111111")
    expect(Object.keys(JSON.parse(lines[0]!)).sort()).toEqual([
      "action",
      "actorId",
      "code",
      "decision",
      "requestId",
      "resourceId",
      "source",
      "type",
    ])
  })
})
