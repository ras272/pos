export async function readJson(
  request: Request
): Promise<{ ok: true; value: unknown } | { ok: false }> {
  try {
    return { ok: true, value: await request.json() }
  } catch {
    return { ok: false }
  }
}

export function createRequestId(): string {
  return crypto.randomUUID()
}

export function successResponse(data: unknown, requestId: string): Response {
  return Response.json(
    { data },
    {
      headers: {
        "Cache-Control": "private, no-store",
        "X-Request-Id": requestId,
      },
    }
  )
}
