# ADR 0002: RLS como frontera de tenant

- Estado: aceptado
- Fecha: 2026-07-26

## Contexto

Web, backoffice y caja pueden cometer errores de filtros o recibir IDs elegidos
por un cliente. Autorizar solo en UI, proxy o API deja el dato expuesto ante un
camino alternativo. Los roles copiados a JWT también quedan obsoletos después de
una baja o suspensión.

## Decisión

PostgreSQL RLS es la frontera final para toda tabla de tenant. Las policies
derivan el actor de `auth.uid()` y consultan `tenant_memberships` vigente como
única autoridad de pertenencia y rol. Todas las capas conservan authn y authz
explícitas, pero ninguna reemplaza RLS. Metadata de JWT nunca autoriza un tenant.

## Consecuencias

- Cada tabla expuesta habilita y fuerza RLS, con grants mínimos y policies por
  operación.
- Bajas y suspensiones se aplican en la siguiente consulta sin esperar otro JWT.
- Tests pgTAP demuestran aislamiento A → B y denegación para no miembros.
- Operaciones privilegiadas requieren helpers mínimos, privados y auditados; una
  clave secreta no es el atajo normal.
