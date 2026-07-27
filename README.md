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

Hoy solo está scaffolded `apps/web`; `apps/admin`, `apps/caja`, `apps/api` y la
capa Supabase siguen siendo arquitectura objetivo, así que todavía no se
consideran localmente ejecutables.

Cada aplicación se desplegará como proyecto Vercel independiente. Ver
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) antes de mover responsabilidades.

## Empezar

```bash
pnpm install
pnpm dev
```

El repositorio requiere pnpm. Los scripts se ejecutan desde la raíz y Turborepo
los distribuye a cada workspace.

## Contratos autoritativos

- Producto y restricciones de Paraguay: [`CLAUDE.md`](CLAUDE.md)
- Arquitectura: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Seguridad de endpoints y auth: [`docs/SECURITY.md`](docs/SECURITY.md)
- Supabase, migraciones y RLS: [`docs/DATABASE.md`](docs/DATABASE.md)
- Flujo de desarrollo: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
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
