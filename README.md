# POS gastronómico para Paraguay

Monorepo para un SaaS de gestión y punto de venta offline-first. La fundación
usa pnpm/Turborepo, Next.js, Vite/React y Supabase con aislamiento multi-tenant
por RLS.

## Arquitectura objetivo

- `apps/web`: marketing público.
- `apps/admin`: backoffice autenticado en Next.js.
- `apps/caja`: POS browser-only en Vite.
- `apps/api`: endpoints HTTP de negocio en Next.js.
- Supabase: capa de datos, RLS y migraciones.

Las cuatro aplicaciones existen, compilan y corren localmente, y la capa
Supabase tiene su esquema de tenancy con RLS forzada y pruebas pgTAP. Lo que
todavía no existe es el dominio del negocio: no hay productos, mesas, comandas,
ventas ni facturación electrónica. Esto es la fundación, no el producto.

Cada aplicación se despliega como proyecto Vercel independiente. Ver
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) antes de mover responsabilidades
y [`docs/VERCEL.md`](docs/VERCEL.md) antes de desplegar.

## Empezar

```bash
cp .env.example .env
pnpm install
pnpm dev
```

El repositorio requiere pnpm y Node 24.18.0. Los scripts se ejecutan desde la
raíz y Turborepo los distribuye a cada workspace. `pnpm build` necesita las
variables de `.env.example`: `apps/caja` falla el build sin sus orígenes,
porque genera su CSP con ellos.

Para la base de datos hacen falta Docker y `pnpm exec supabase start`; el
detalle está en [`supabase/README.md`](supabase/README.md).

## Contratos autoritativos

- Producto y restricciones de Paraguay: [`CLAUDE.md`](CLAUDE.md)
- Arquitectura: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Seguridad de endpoints y auth: [`docs/SECURITY.md`](docs/SECURITY.md)
- Supabase, migraciones y RLS: [`docs/DATABASE.md`](docs/DATABASE.md)
- Flujo de desarrollo: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
- Despliegue y ambientes: [`docs/VERCEL.md`](docs/VERCEL.md)
- Bloqueantes de producción:
  [`docs/PRODUCTION_READINESS.md`](docs/PRODUCTION_READINESS.md)
- Checklist de PR:
  [`docs/PULL_REQUEST_CHECKLIST.md`](docs/PULL_REQUEST_CHECKLIST.md)
- Contrato visual: [`packages/ui/DESIGN.md`](packages/ui/DESIGN.md)

No se inventan nombre, planes, alcance v1, proveedor de facturación ni dirección
visual. Las decisiones técnicas relevantes se registran en `docs/adr/`.

## UI compartida

`@workspace/ui` es el design system shadcn v4/base-luma. Los componentes se
agregan desde la raíz y se consumen mediante sus exports:

```bash
pnpm dlx shadcn@latest add button -c apps/web
```

```tsx
import { Button } from "@workspace/ui/components/button"
```
