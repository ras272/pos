# Arquitectura

Este documento define los límites del monorepo. Las reglas de seguridad y base
de datos viven en [SECURITY.md](./SECURITY.md) y [DATABASE.md](./DATABASE.md).

## Desplegables

Cada aplicación es un proyecto Vercel independiente, con variables, previews,
dominios y promociones separados.

| Aplicación   | Runtime    | Responsabilidad                                                                         |
| ------------ | ---------- | --------------------------------------------------------------------------------------- |
| `apps/web`   | Next.js    | Marketing público y estático. No contiene negocio autenticado.                          |
| `apps/admin` | Next.js    | Backoffice autenticado y sus Server Actions. No publica endpoints HTTP de negocio.      |
| `apps/caja`  | Vite/React | POS offline-first que corre solo en el navegador. No puede importar código de servidor. |
| `apps/api`   | Next.js    | Único host de Route Handlers HTTP de negocio consumidos por otros clientes.             |

Un deploy no comparte secretos por conveniencia con otro. Local, preview y
producción también son ambientes distintos; una preview nunca apunta a datos o
credenciales de producción.

## Dirección de dependencias

```text
apps/*  ──pueden importar──>  packages/*
packages/*  ──nunca importan──>  apps/*
```

- `apps/caja` importa únicamente exports explícitamente browser-safe.
- Un paquete con código de navegador y servidor ofrece subpaths separados. No
  existe un barrel raíz que mezcle ambos lados.
- Los adaptadores de Next.js para cookies, proxy, request y response quedan en
  `apps/admin` o `apps/api`; no se esconden en paquetes agnósticos.
- Solo `apps/api` puede contener `route.ts` con handlers HTTP de negocio. Los
  handlers técnicos de framework requieren revisión explícita y no pueden
  convertirse en una segunda API.
- Las aplicaciones reciben DTOs y tipos compartidos; no dependen de los
  detalles internos de otra aplicación.

## Flujo de datos

Los clientes de navegador y SSR usan la clave publicable de Supabase y tipos
generados. La identidad verificada se propaga a un cliente con alcance de
usuario; PostgreSQL RLS aplica el límite final de tenant.

`apps/api` concentra integraciones y operaciones HTTP de negocio. `apps/admin`
puede ejecutar Server Actions, pero cada una se trata como un POST público y
delega acceso a datos a un DAL `server-only`. Ambos caminos cumplen el contrato
de [SECURITY.md](./SECURITY.md#controles-obligatorios-de-un-entrypoint).

No se incorpora una clave secreta o cliente administrativo hasta que exista un
caso concreto, aislado y aprobado. Tener código en Vercel no lo vuelve confiable
por sí solo.

## Contratos transversales

- SQL versionado en `supabase/migrations/` es la única fuente de verdad del
  esquema; ver [DATABASE.md](./DATABASE.md).
- `packages/ui/DESIGN.md` manda sobre cualquier UI.
- `CLAUDE.md` conserva las restricciones de Paraguay y las decisiones de
  producto. Esta arquitectura no modifica SIFEN, IVA, guaraníes ni offline-first.
- Una decisión que cambie estos límites requiere un ADR nuevo o reemplazante.
