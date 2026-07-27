import react from "@vitejs/plugin-react"
import { defineConfig, loadEnv, type Plugin } from "vite"

import { cajaContentSecurityPolicy } from "./src/security/csp.js"

const inlineScript = /<script(?![^>]*\ssrc\s*=)[^>]*>[\s\S]*?<\/script>/i

/**
 * Inyecta la CSP en el HTML del build. Corre solo en `build`: en `dev` Vite
 * necesita su cliente inline y una CSP estricta lo rompería.
 *
 * Si falta un origen, el build falla. Publicar la caja sin CSP declarada sería
 * peor que no publicarla: es la app que maneja la venta.
 */
function contentSecurityPolicy(env: Record<string, string>): Plugin {
  return {
    name: "caja-content-security-policy",
    apply: "build",
    transformIndexHtml: {
      order: "post",
      handler(html) {
        const policy = cajaContentSecurityPolicy({
          apiUrl: env.VITE_API_URL,
          supabaseUrl: env.VITE_SUPABASE_URL,
        })

        if (inlineScript.test(html)) {
          throw new Error(
            "The caja build emitted an inline script, which its CSP forbids"
          )
        }

        return html.replace(
          "<head>",
          `<head>\n    <meta http-equiv="Content-Security-Policy" content="${policy}" />`
        )
      },
    },
  }
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "")

  return {
    plugins: [react(), contentSecurityPolicy(env)],
  }
})
