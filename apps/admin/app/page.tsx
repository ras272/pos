import { connection } from "next/server"

/**
 * El backoffice se renderiza por request: la CSP con nonce necesita un nonce
 * nuevo por visita, y una página estática se genera cuando todavía no existe
 * ninguna request donde inyectarlo.
 */
export default async function Page() {
  await connection()

  return (
    <main>
      <h1>Admin listo</h1>
      <p>Backoffice autenticado en esqueleto.</p>
    </main>
  )
}
