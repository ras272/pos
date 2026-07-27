# Despliegue en Vercel y topología de Supabase

Este documento define cómo se despliega el monorepo. Los límites entre
aplicaciones están en [ARCHITECTURE.md](./ARCHITECTURE.md); lo que hay que
probar antes de la primera promoción a producción está en
[PRODUCTION_READINESS.md](./PRODUCTION_READINESS.md).

## Cuatro proyectos, no uno

Cada aplicación es un proyecto Vercel independiente. No se comparten variables,
dominios ni promociones: un despliegue de marketing no puede arrastrar consigo
credenciales del backoffice.

| Proyecto | Root Directory | Framework | Build        | Output  |
| -------- | -------------- | --------- | ------------ | ------- |
| `web`    | `apps/web`     | Next.js   | `next build` | `.next` |
| `admin`  | `apps/admin`   | Next.js   | `next build` | `.next` |
| `api`    | `apps/api`     | Next.js   | `next build` | `.next` |
| `caja`   | `apps/caja`    | Vite      | `vite build` | `dist`  |

En los cuatro, el Install Command es `pnpm install --frozen-lockfile` y la raíz
del repositorio es la del monorepo, no la de la app.

## Variables por proyecto

Ninguna es secreta: la clave publicable de Supabase está pensada para viajar al
navegador y el límite real lo aplica RLS. Aun así se cargan por proyecto, porque
un proyecto no tiene por qué conocer los orígenes de otro.

| Variable                               | web | admin | api | caja |
| -------------------------------------- | --- | ----- | --- | ---- |
| `NEXT_PUBLIC_SUPABASE_URL`             |     | ✔     | ✔   |      |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` |     | ✔     | ✔   |      |
| `NEXT_PUBLIC_API_URL`                  |     | ✔     |     |      |
| `ADMIN_ORIGIN`                         |     |       | ✔   |      |
| `CAJA_ORIGIN`                          |     |       | ✔   |      |
| `VITE_SUPABASE_URL`                    |     |       |     | ✔    |
| `VITE_SUPABASE_PUBLISHABLE_KEY`        |     |       |     | ✔    |
| `VITE_API_URL`                         |     |       |     | ✔    |

`caja` **no compila** sin `VITE_SUPABASE_URL` ni `VITE_API_URL`: su CSP se
genera con esos orígenes exactos durante el build, y un build sin ellos
publicaría la app de venta sin política declarada. Es una falla deliberada, no
un descuido.

`ADMIN_ORIGIN` y `CAJA_ORIGIN` son los únicos orígenes que `api` acepta por
CORS. No admiten comodines: un origen que no esté listado no recibe
`Access-Control-Allow-Origin` y el navegador descarta la respuesta.

## Local, preview y producción son tres ambientes

Cada uno con sus propias variables en Vercel (Development / Preview /
Production). Reglas que no se negocian:

- **Una preview nunca apunta a Supabase de producción.** Una rama sin revisar
  no puede escribir sobre datos de clientes reales.
- Las previews quedan con **Deployment Protection** activada. Una URL de preview
  del backoffice es una pantalla autenticada expuesta a internet.
- Producción se promueve desde `main` y solo después de que pasen los checks
  requeridos.
- El alcance de cada variable es el proyecto que la usa. No existe una variable
  de equipo compartida entre las cuatro apps.

## URLs de redirección de Auth

Supabase rechaza cualquier redirección que no esté en su allowlist. Hay que
cargar, por ambiente, el `Site URL` y las `Redirect URLs` del backoffice y de la
caja. Las URLs de preview cambian en cada despliegue: si se necesita login en
preview, se usa el patrón con comodín que Supabase acepta **solo** para
previews, nunca para producción.

## Topología de Supabase

```text
local (docker)  →  proyecto no productivo  →  proyecto de producción
```

- **Local** es la fuente de verdad durante el desarrollo. `supabase db reset`
  reconstruye desde `supabase/migrations/` y corre las pruebas pgTAP.
- Una migración se promueve en orden: local → no productivo → producción. Nunca
  se aplica un cambio directamente en producción desde un editor SQL.
- Antes de cada promoción se corre el chequeo de deriva: si el esquema remoto no
  coincide con las migraciones versionadas, alguien tocó la base por afuera y
  eso se resuelve antes de seguir.
- `pnpm db:types:check` regenera los tipos desde local y los compara byte a byte
  contra los versionados. Si difieren, el contrato de tipos quedó viejo.
- El restore de backup se **ensaya**, no se asume. Un backup que nunca se
  restauró no es un backup.

## Qué falta antes de la primera promoción

Lo que hoy no está resuelto está listado como bloqueante en
[PRODUCTION_READINESS.md](./PRODUCTION_READINESS.md). Los dos más grandes: no
hay backend de rate limiting (en producción la API falla cerrada a propósito) y
`web` todavía no tiene CSP.
