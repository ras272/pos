# DESIGN.md — reglas de UI

Contrato obligatorio para todo código de UI del proyecto. Si una pantalla contradice este
documento, la pantalla está mal. Se lee en 30 segundos; no es un manual.

## 1. base-luma y tokens

`@workspace/ui` (`packages/ui`) **es** el design system: shadcn v4, style `base-luma`, sobre
Base UI (`@base-ui/react`), **no Radix**. Tailwind v4 CSS-first.

Todos los tokens viven en **`packages/ui/src/styles/globals.css`**: declarados en `:root` y en
`.dark`, registrados en `@theme inline` como `--color-<nombre>`. Sin las tres cosas, la clase no
existe. No hay archivo de config JS: el único lever es ese CSS.

## 2. Área de toque

La app se usa con el dedo, en tablet, de pie, con luz mala y turnos largos.

- **Mínimo 44px** de alto y ancho en cualquier cosa tocable. **Objetivo 48px.**
- En la caja y en cualquier pantalla táctil: `size="touch"` (h-12, text-base, font-semibold, px-6)
  y `size="icon-touch"` (48×48).
- **Prohibido `size="xs"` y `size="sm"`** en pantallas táctiles. Solo backoffice de escritorio.
- Un chip de estado **no tocable** no lleva apariencia de botón. Si es tocable, aplica el mínimo.

## 3. Radio

`--radius` es **`0.5rem`**. La escala (`sm` ×0.6 … `4xl` ×2.6 = 20,8px) se deriva sola.

- **No se sobreescribe el radio por componente.** El único lever es el token.
- Ojo: `cn` usa `tailwind-merge`, así que un `rounded-lg` en `className` **sí** pisa al `rounded-4xl`
  del componente (verificado: `twMerge("rounded-4xl","rounded-lg")` → `rounded-lg`). Nada en el
  código lo impide: es regla de revisión. Si el radio no te gusta, se cambia `--radius`.

## 4. Guaraníes

Sin decimales. Separador de miles con **punto**. Prefijo `Gs `. Ejemplo: `Gs 85.000`.
Ticket promedio real ~Gs 85.000: montos de 6 y 7 dígitos son lo normal, no el caso borde.

- Usar **siempre** `formatGs` de `@workspace/ui/lib/format`. Nunca `toLocaleString` suelto,
  nunca interpolación a mano, nunca un formateador local del feature.
- Toda columna o celda de montos lleva la utilidad **`guaranies`** (cifras tabulares +
  alineación a la derecha). Sin eso los dígitos bailan al actualizarse y no se pueden comparar
  dos filas de un vistazo.
- Los totales grandes no se abrevian (`Gs 1,2M` está prohibido en pantallas operativas).

## 5. IVA

- IVA **por ítem, nunca por negocio**: 10% servicios, 5% ciertos bienes de canasta.
- Los precios que se muestran y se cobran **ya incluyen IVA**. Se desagrega dividiendo
  por 1,1 o 1,05 según el ítem.
- En comprobantes, cierres y arqueos se muestra el **desglose de 10% y 5% en líneas separadas**.
  Nunca una sola línea "IVA".

## 6. Umbral innominado

Valor actual **Gs 7.000.000**. Es **configurable**, no una constante: ya bajó de 35M a 7M por
decreto. Leerlo de configuración, siempre.

Cuando el total alcanza o supera el umbral, la pantalla de cobro **bloquea el cierre** hasta
capturar RUC o cédula:

- el total y el campo de identificación se tiñen en `warning`;
- el input de RUC/cédula pasa a requerido;
- **Cobrar queda deshabilitado** hasta que haya un identificador válido.

Por encima del umbral SIFEN rechaza el innominado (código 1321). El color acompaña la regla,
nunca la reemplaza.

## 7. Tokens de estado

Cinco hues, ninguno más: **27 rojo, 70 ámbar, 152 verde, 236 cian, 292 violeta.**
Hue fijo por token en los dos temas: entre `:root` y `.dark` solo sube la luminosidad.

| Token | Cuándo se usa | Cuándo NO |
|---|---|---|
| `success` | Resultado positivo, cerrado y **confirmado**: documento aprobado por SIFEN, cobro acreditado, arqueo que cuadra, comanda lista. Sólido solo en la confirmación de cobro a pantalla completa. | "Firmado y en cola" (eso es `info`); "hay internet"; como color de acción (Cobrar es `primary`); relleno grande en listas donde casi todo está aprobado. |
| `warning` | Urgente, accionable y **sin incumplimiento todavía**: ventana de 72 h en aviso, umbral innominado alcanzado, comanda demorada, cuenta pedida, stock bajo, certificado F1 por vencer. | Si ya falló o venció (`destructive`); si no hay nada que hacer ahora (`info`); "sin conexión". |
| `info` | En curso o de contexto, sin acción y sin alarma: **sin conexión** (chip permanente de la barra de estado), documento **en cola** y contador "N pendientes", sincronizando, comanda enviada, mesa reservada. | En nada tocable (violeta es "esto se toca"); cuando el reloj apremia (`warning`); cuando ya se resolvió (`success`); como reemplazo de `muted-foreground` para jerarquía baja. |
| `destructive` | **Sólido** = estado grave no tocable: "RECHAZADO POR SIFEN", ventana de 72 h vencida, certificado F1 vencido. **Teñido** = acción destructiva tocable: Anular venta, Eliminar ítem, `aria-invalid`. | "Sin conexión"; "quedan 6 h"; cualquier cosa que no sea grave. Cada rojo de más le quita valor al rojo que sí importa. |

Los `--chart-*` **no son estados**. No los uses para estado.

## 8. Reglas de uso

- Un estado de sincronización **nunca** usa `destructive`, salvo rechazo de SIFEN o 72 h vencidas.
- "Sin conexión" va en `info` teñido. Nunca en rojo, nunca en gris. En offline-first es operación normal.
- **Rojo teñido = acción tocable. Rojo sólido = estado grave no tocable.** No mezclar registros.
- "RECHAZADO POR SIFEN" va siempre sólido (`bg-destructive` + `text-destructive-foreground`).
  Nunca `bg-destructive/10`: mide 3,99:1 y no cumple.
- Nada se pinta de `success` antes del acuse de SIFEN. Firmado y en cola es `info`.
- `warning` solo si hay una acción a un toque de distancia. Si no hay nada que hacer, es `info`.
- Ventana de 72 h: `info` mientras sobra → `warning` teñido al entrar en aviso → `warning` sólido
  bajo el umbral crítico → `destructive` sólido si venció.
- Nunca `primary` (violeta) para un estado: el violeta significa "esto se toca".
- Nunca `muted` ni `muted-foreground` como estado: el gris se lee como deshabilitado, no como dato.
- **Todo estado lleva ícono propio y texto.** El color nunca es el único canal: simulando
  deuteranopia, `warning` y `destructive` quedan a ΔE76 ≈ 11, y en `.dark` `success` y
  `destructive` a ≈ 13. Indistinguibles de un vistazo.
- Teñido = `/10` en claro, `/20` en oscuro. El tinte no porta la información: la porta el texto
  en color pleno.
- En `.dark` los estados **aclaran** y su `-foreground` es casi negro. Nunca blanco sobre un
  estado sólido en tema oscuro.
- El mapeo estado → variante de `Badge`/`Alert` va en un `Record` de TypeScript, no en CSS.

## 9. Prohibido

- Usar `destructive` para estados de sincronización.
- Inventar colores fuera de los tokens: sin hex sueltos, sin `oklch()` inline, sin clases
  `text-red-500`/`bg-green-*` de la paleta de Tailwind, sin un sexto hue.
- Hardcodear el formato de guaraníes en vez de `formatGs`.
- Alias CSS de dominio (`--sync-*`, `--mesa-*`, `--comanda-*`).
- Sobreescribir el radio o los tamaños táctiles por instancia.
- Tratar el umbral innominado o el umbral de aviso de las 72 h como constantes literales.
