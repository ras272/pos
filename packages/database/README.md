# @workspace/database

Tipos TypeScript generados desde Supabase local.

## Contrato

- `src/database.types.ts` se genera con `pnpm db:types`.
- No editar los tipos de tablas a mano.
- El export público del paquete es solo de tipos; no crea clientes, conexiones
  ni transporta secretos.

## Verificación

```bash
pnpm db:types:check
```

El check resetea la base local, regenera los tipos a un archivo temporal y
falla si hay drift contra `src/database.types.ts`.
