begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists plpgsql_check with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- La asercion que cierra la familia entera de errores que aparecio seis veces en
-- este esquema.
--
-- plpgsql no valida el cuerpo de una funcion al crearla: resuelve columnas y
-- tablas en tiempo de ejecucion. Por eso se pudieron crear, sin una sola queja,
-- funciones que leian tenants.ruc antes de que existiera, que escribian
-- sifen_response_code sobre una tabla que tiene response_code, que dejaban en
-- null una columna NOT NULL, y un trigger compartido que asumia la forma de una
-- sola de las tres tablas donde estaba colgado.
--
-- Ninguna prueba estructural podia verlo: el objeto existia, los grants estaban,
-- las policies estaban. Solo aparecia al recorrer el camino, y el camino recien
-- se recorrio cuando alguien intento cobrar.
--
-- plpgsql_check hace el analisis estatico que plpgsql no hace. Con esto, una
-- funcion nueva que referencie una columna inexistente rompe el CI sin que nadie
-- tenga que acordarse de ejercitar su rama.

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    cross join lateral extensions.plpgsql_check_function_tb(routine.oid) as finding
    where routine_schema.nspname in ('public', 'security')
      and routine.prolang = (select oid from pg_catalog.pg_language where lanname = 'plpgsql')
      and routine.prorettype <> 'pg_catalog.trigger'::regtype
      and finding.level = 'error'
  ),
  'ninguna funcion de public o security tiene errores de analisis estatico'
);

-- Las funciones trigger se validan UNA VEZ POR TABLA a la que estan colgadas, no
-- una vez por funcion. Es exactamente lo que caza un trigger compartido que
-- supone la forma de una sola tabla: require_open_cash_session leia
-- adjusts_cash_session_id, que existe en cash_movements pero no en payments ni en
-- payment_reversals, y validarla contra una sola de las tres la habria dado por
-- buena.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    join pg_catalog.pg_proc routine on routine.oid = trigger_row.tgfoid
    cross join lateral extensions.plpgsql_check_function_tb(
      routine.oid,
      trigger_row.tgrelid
    ) as finding
    where not trigger_row.tgisinternal
      and finding.level = 'error'
  ),
  'ninguna funcion trigger tiene errores contra ninguna de las tablas donde esta colgada'
);

-- Que el analisis se este corriendo de verdad y no sobre un conjunto vacio: si un
-- refactor futuro rompe el join, las dos aserciones de arriba pasarian solas.
select cmp_ok(
  (
    select pg_catalog.count(*)::int
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    where routine_schema.nspname in ('public', 'security')
      and routine.prolang = (select oid from pg_catalog.pg_language where lanname = 'plpgsql')
  ),
  '>=',
  30,
  'el analisis recorre las funciones plpgsql del esquema y no un conjunto vacio'
);

select cmp_ok(
  (
    select pg_catalog.count(*)::int
    from pg_catalog.pg_trigger trigger_row
    where not trigger_row.tgisinternal
  ),
  '>=',
  50,
  'el analisis de triggers recorre todas las combinaciones de funcion y tabla'
);

select * from finish();

rollback;
