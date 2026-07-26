# POS para gastronomía — Paraguay

SaaS de gestión y punto de venta para restaurantes, lomiterías, cafés y bares en Paraguay.
Greenfield: **no hay código todavía**. No hay stack elegido. No hay UI.

Referencia de categoría: frambuesa.app (POS cloud argentino). Es referencia, **no** modelo a copiar.

---

## Decidido

- **Mercado:** Paraguay, 100%. No es un producto regional con Paraguay adentro.
- **Segmento de entrada:** restaurante / lomitería / hamburguesería / cafetería **con salón**,
  1 a 3 sucursales, formal (con RUC y facturando), Asunción y Gran Asunción.
- **Las 3 cuñas** (toda decisión de producto se evalúa contra estas; si una feature no refuerza
  ninguna, va al backlog):
  1. **Offline-first real** — funciona sin internet, de verdad
  2. **Precio público en guaraníes + self-serve** — nadie en el mercado publica precios
  3. **Integración con delivery** — PedidosYa / Monchis

---

## Sin decidir — no asumir

| Qué | Estado |
|---|---|
| Nombre del producto | **abierto** (en un prototipo descartado se usó "ñande" como placeholder — no está elegido) |
| Stack técnico | **abierto** |
| Dirección visual / UI | **abierto** — un primer prototipo se descartó por completo |
| Estructura y monto de planes | **abierto** — la banda de mercado es Gs 190.000–450.000/mes |
| Proveedor de facturación electrónica | **abierto** — hay recomendación, no decisión |
| Alcance exacto de la v1 | **abierto** — hay una auditoría de features en curso |

---

## Restricciones duras de Paraguay

Esto no es opinión ni preferencia: sale de la normativa vigente y condiciona cualquier pantalla
que se diseñe. Verificar contra fuente antes de cambiar cualquiera de estos puntos.

**Facturación (SIFEN / DNIT — no AFIP, no ARCA):**
- **Ventana de 72 h** desde la firma para transmitir el documento. Esto es lo que hace legalmente
  viable operar offline: se emite, se firma, se imprime y se entrega sin conexión, y se transmite
  al reconectar. El modo contingencia formal está deshabilitado (rechazo 1050); la ventana de 72 h
  **es** la contingencia.
- **Umbral de Gs 7.000.000**: por encima de ese monto SIFEN rechaza el comprobante innominado
  (código 1321). La pantalla de cobro tiene que **forzar la captura de RUC o cédula antes de
  cerrar la venta**. El umbral ya bajó de 35M a 7M por decreto → debe ser configurable, no constante.
- **IVA por ítem**, nunca por negocio: 10% servicios, 5% ciertos bienes de canasta.
- **Precios con IVA incluido** (se desagrega dividiendo por 1,1 / 1,05).
- **Un local = un establecimiento. Una caja = un punto de expedición**, cada uno con su propio
  contador de numeración correlativa.
- **Impresora térmica obligatoria**: a pedido del comprador hay que entregar el comprobante impreso.
- Cada cliente necesita su propio certificado F1, que **vence cada año** y se tramita presencialmente.

**Cobros (PY-QR, estándar del BCP):**
- El QR interoperable es 8 de cada 10 pagos digitales del país.
- La spec ya trae nativos: **propina** (campos 55/56/57), **nº de factura** (62-01),
  **ID de terminal** (62-07), **MCC 5812 = restaurantes**. Solo PYG, montos sin decimales.
- **No existe open banking en Paraguay.** No hay APIs bancarias públicas ni lectura de cuentas.

**Moneda:** guaraníes, sin decimales, separador de miles con punto (`Gs 85.000`).
Ticket promedio real en restaurantes: ~Gs 85.000.

---

## Competencia, en corto

- **e-Karú** (restaurante.com.py) — el líder local, 1.500+ locales, SIFEN nativo.
  No publica precios, no ofrece trial, no menciona offline.
- **Fudo** (fu.do/es-py) — el mejor producto cloud de la región, opera en PY.
  **No tiene facturación electrónica paraguaya** y su FAQ dice textual que necesita internet permanente.
- Otros locales: HPTI, Alysoft, TPV, Redtouch, Mesa Inteligente.
- **e-Kuatia'i** (gratis, de la DNIT) cubre al local de una sola caja. El argumento de upgrade no es
  "te facturo" sino el techo: 1 establecimiento, 1 punto de expedición.

---

## Dónde está lo demás

La investigación de mercado, regulatoria y competitiva está en la memoria del proyecto
(`memory/`), no en este archivo. Este archivo es solo el piso común entre sesiones.

**Al trabajar acá:** escribir en español. No inventar features, precios ni decisiones
que no estén en la lista de "Decidido". Si algo hace falta y no está resuelto, preguntarlo.
