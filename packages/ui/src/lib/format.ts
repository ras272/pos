// Sin Intl ni toLocaleString: el formato no puede depender del ICU del runtime
// ni del locale de la tablet. Guaraníes sin decimales, miles con punto.
export function formatGs(n: number): string {
  if (!Number.isFinite(n)) return "Gs 0"
  const entero = Math.round(n)
  const signo = entero < 0 ? "-" : ""
  let resto = Math.abs(entero).toString()
  let miles = ""
  while (resto.length > 3) {
    miles = "." + resto.slice(-3) + miles
    resto = resto.slice(0, -3)
  }
  return `${signo}Gs ${resto}${miles}`
}

/**
 * El precio ya viene con IVA incluido: se desagrega dividiendo por 1,1 o 1,05.
 * El IVA sale por resta para que base + iva sea exactamente el total cobrado.
 */
export function desglosarIva(bruto: number, tasa: 10 | 5): { base: number; iva: number } {
  const total = Math.round(bruto)
  const base = Math.round(total / (tasa === 10 ? 1.1 : 1.05))
  return { base, iva: total - base }
}
