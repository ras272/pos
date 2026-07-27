import type { NextRequest } from "next/server"

import { updateSession } from "./lib/supabase/proxy"

export async function proxy(request: NextRequest) {
  return updateSession(request)
}

export const config = {
  matcher: [
    /*
     * Todo salvo estÃ¡ticos y assets. Los `_next/data` igual pasan por acÃ¡: Next
     * los incluye a propÃ³sito para que proteger una pÃ¡gina no deje su ruta de
     * datos abierta.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
}
