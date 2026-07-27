export function errorResponse(
  status: number,
  code: string,
  requestId: string,
  headers?: HeadersInit
): Response {
  const responseHeaders = new Headers(headers)
  responseHeaders.set("Cache-Control", "private, no-store")
  responseHeaders.set("X-Request-Id", requestId)
  return Response.json(
    { error: { code }, requestId },
    { headers: responseHeaders, status }
  )
}
