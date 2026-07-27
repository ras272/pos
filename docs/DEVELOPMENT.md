# Desarrollo

## Antes de cambiar código

1. Leer `CLAUDE.md` para contexto de Paraguay y decisiones de producto.
2. Leer `packages/ui/DESIGN.md` si el cambio toca UI.
3. Leer [ARCHITECTURE.md](./ARCHITECTURE.md), [SECURITY.md](./SECURITY.md) y
   [DATABASE.md](./DATABASE.md) según el área.
4. Para Next.js, consultar la guía relevante instalada en
   el `node_modules` del workspace que realmente tenga Next instalado, por
   ejemplo `apps/web/node_modules/next/dist/docs/`; no asumir un
   `node_modules/` en la raíz. Esta versión tiene cambios incompatibles con
   conocimiento previo.

No se inventan nombre, precios, alcance v1, proveedor SIFEN ni dirección visual.
Si una decisión abierta bloquea el trabajo, se pregunta.

## Flujo del monorepo

- Instalar desde la raíz con `pnpm install` y conservar el lockfile.
- Ejecutar aplicaciones con `pnpm dev`; usar filtros de pnpm para un workspace.
- Las apps importan packages, nunca al revés. `caja` solo consume exports de
  navegador y no puede depender de `server-only`, Node.js o adaptadores Next.
- Mantener módulos pequeños y con una sola responsabilidad. Extraer contratos
  compartidos a packages solo cuando no acoplen runtimes.
- Los Route Handlers de negocio viven solo en `apps/api`. Las Server Actions de
  `apps/admin` usan el wrapper seguro y un DAL `server-only`.

## Cambios de base de datos

1. Crear una migración SQL en `supabase/migrations/`.
2. Escribir o actualizar tests pgTAP de aislamiento y estructura.
3. Resetear Supabase local desde cero y ejecutar los tests.
4. Regenerar los tipos desde local y comprobar que no hay drift.
5. Revisar la lista de [DATABASE.md](./DATABASE.md#revisión-de-migraciones).

No se modifica producción desde Dashboard, no se editan tipos generados y no se
introduce Drizzle como segunda fuente de migraciones.

## Verificación

Durante la fundación, ejecutar primero las verificaciones enfocadas disponibles
y después el check completo definido por el repositorio. Para cambios solo de
Markdown:

```bash
pnpm prettier --check docs AGENTS.md CLAUDE.md README.md
```

Antes de entregar, revisar el diff para evitar secretos, decisiones de producto
no aprobadas y duplicación de contratos. Todo endpoint nuevo debe demostrar los
controles de [SECURITY.md](./SECURITY.md#controles-obligatorios-de-un-entrypoint).

## Decisiones

Los ADR en `docs/adr/` explican por qué existe una frontera. No se reescriben
para ocultar el pasado: una decisión nueva agrega un ADR que reemplaza al
anterior y actualiza los documentos autoritativos.
