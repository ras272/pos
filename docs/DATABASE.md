# Base de datos

Supabase Postgres se administra con migraciones SQL versionadas. Los tipos
TypeScript se generan desde una base local reseteada y nunca se editan a mano.

## Fuente de verdad

`supabase/migrations/` es la única historia canónica del esquema, policies,
grants, funciones, triggers e índices. Una migración debe poder reconstruir una
base vacía y pasar pgTAP. Cambios manuales en Dashboard o SQL no versionado se
consideran drift y no se promocionan.

Drizzle queda diferido. Mantener migraciones SQL y de ORM en paralelo crea dos
fuentes de verdad; una conexión directa del ORM también puede perder el contexto
JWT del Data API y saltarse la frontera esperada de RLS. La decisión completa
está en [ADR 0001](./adr/0001-supabase-sql-over-drizzle.md).

## Invariantes de tenant

- Toda fila propiedad de un tenant tiene `tenant_id NOT NULL`, una relación
  válida al tenant y un índice que soporte esa relación.
- `tenant_id` es inmutable después del insert. Mover una fila entre tenants no
  es una actualización válida.
- `tenant_memberships` es la única autoridad de pertenencia y rol. Ningún claim
  de metadata del JWT reemplaza esa consulta.
- Tenant suspendido o membresía suspendida no concede acceso.
- Los clientes no insertan, actualizan ni borran membresías directamente. Un RPC
  futuro debe ser atómico, auditado y conservar al menos un `owner`.
- IDs de usuario o rol enviados por el cliente nunca determinan la identidad del
  actor. Las funciones derivan el usuario de `auth.uid()`.

## RLS y grants

Cada tabla expuesta propiedad del proyecto:

- habilita y fuerza RLS;
- tiene policies separadas por `SELECT`, `INSERT`, `UPDATE` y, solo si está
  justificado, `DELETE`;
- usa `USING` para filas existentes y `WITH CHECK` para el estado nuevo;
- verifica membresía, rol y estado vigentes en cada operación;
- niega por defecto a no miembros y nunca depende de filtros de aplicación.

Los permisos SQL son una capa adicional. Se revocan privilegios implícitos de
`PUBLIC`, se niega `CREATE` en schemas de aplicación y se configuran default
privileges restrictivos. `anon` y `authenticated` reciben únicamente
`USAGE`/`SELECT`/`INSERT`/`UPDATE` o `EXECUTE` concretos. No reciben
`TRUNCATE`; `DELETE` físico no se expone a clientes.

Toda vista expuesta a clientes debe cumplir una de estas dos condiciones:

- declararse con `security_invoker = true`; o
- permanecer fuera de exposición, con grants revocados para que no sea
  alcanzable por el Data API.

Una vista expuesta por accidente es una fuga de superficie, no un detalle de
implementación. Las vistas nuevas o modificadas también requieren cobertura de
pgTAP que pruebe el acceso esperado y el acceso denegado.

## Funciones

`SECURITY INVOKER` es el valor normal. Una función `SECURITY DEFINER` exige:

- necesidad documentada y revisión específica;
- `search_path` vacío, nombres totalmente calificados y nada de SQL dinámico;
- owner controlado y `EXECUTE` revocado de `PUBLIC` y roles no necesarios;
- schema privado `security`, fuera del Data API, para helpers privilegiados;
- inputs que no permitan elegir actor o rol y validación explícita de
  `auth.uid()`.

Si hace falta exponer un RPC, un wrapper público `SECURITY INVOKER` delega al
helper privado mínimo. Las funciones expuestas devuelven DTOs acotados, no
tablas internas completas.

## Índices y borrado lógico

Toda foreign key y columna usada de forma habitual en policies o joins de
tenant tiene un índice apropiado; las restricciones únicas deben respetar el
alcance del tenant. Cada migración se revisa con `EXPLAIN` cuando cambia un
camino crítico.

Cuando el dominio necesite “borrar”, se usa estado o `deleted_at` y se conserva
la fila para auditoría y sincronización offline. Las lecturas normales excluyen
filas borradas; restauración, retención y unicidad se definen en la misma
migración. El borrado físico queda reservado a un proceso interno de retención
aprobado, nunca a un cliente Supabase.

## Revisión de migraciones

Una revisión confirma, como mínimo:

- reset limpio, pgTAP y regeneración de tipos sin drift;
- RLS forzado, policies por operación y grants mínimos para cada objeto nuevo;
- inmutabilidad de tenant y aislamiento A → B en lectura y escritura;
- funciones, views y schemas sin exposición privilegiada accidental; las
  vistas expuestas cumplen `security_invoker = true` o quedan fuera de
  exposición;
- pgTAP cubre las vistas y funciones nuevas o modificadas;
- índices para foreign keys y predicados de policy;
- estrategia de rollback o forward-fix y efecto sobre datos existentes;
- compatibilidad con sincronización offline y obligaciones de Paraguay cuando
  el cambio toca facturación, IVA, numeración o identidad fiscal.
