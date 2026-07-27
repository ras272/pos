# ADR 0001: SQL de Supabase antes que Drizzle

- Estado: aceptado
- Fecha: 2026-07-26

## Contexto

La frontera multi-tenant depende de RLS, grants, funciones y triggers de
PostgreSQL. Supabase ya necesita migraciones SQL para representar esos objetos.
Agregar las migraciones de Drizzle mantendría una segunda historia parcial del
esquema. Además, una conexión Postgres directa no trae automáticamente el JWT y
el contexto de `auth.uid()` usados por las policies del Data API.

## Decisión

Las migraciones SQL bajo `supabase/migrations/` son la única fuente de verdad.
Los clientes usan tipos generados desde Supabase y, por defecto, conexiones con
alcance de usuario a través de la clave publicable. No se incorpora Drizzle en
esta fundación.

## Consecuencias

- Reset local, pgTAP y generación de tipos validan una misma historia.
- Policies, grants e índices se revisan junto con el cambio de esquema.
- No hay acceso directo a Postgres desde código de aplicación por conveniencia.
- Drizzle puede reevaluarse para consultas tipadas si conserva SQL como única
  migración, no duplica el modelo y demuestra que no debilita el contexto RLS.
