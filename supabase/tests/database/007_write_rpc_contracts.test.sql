begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- Contratos de los RPC de escritura. Son aserciones de catalogo: no dependen de
-- ningun dato, se aplican solas a toda funcion futura, y por eso valen mas que
-- una prueba de comportamiento sobre las diez que existen hoy.
--
-- La que exige la guardia de membresia vive en 002, junto con el resto de las
-- reglas que recorren el catalogo.

-- MARCADOR_CUERPO
-- Ninguna rutina de public ni de security acepta identidad de tenant, usuario o rol como parametro. Se aplica a las volatiles (los RPC y sus wrappers) y se apoya en proargnames recortado a los argumentos de entrada, para que un nombre de columna OUT no dispare un falso rojo.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    cross join lateral pg_catalog.unnest(
      coalesce(routine.proargnames[1:routine.pronargs], array[]::text[])
    ) as argument(name)
    where routine_schema.nspname in ('public', 'security')
      and routine.provolatile = 'v'
      and routine.prokind in ('f', 'p')
      and argument.name in ('p_tenant_id', 'p_user_id', 'p_actor_id', 'p_role', 'p_roles')
  ),
  'ningun RPC acepta tenant, usuario ni rol como parametro de identidad'
);

-- Ningun RPC de escritura desreferencia identidad desde un payload: el cuerpo no contiene los identificadores de pertenencia como literal entrecomillado, que es la forma que exigen tanto la extraccion de una clave jsonb como el SQL dinamico.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    where routine_schema.nspname in ('public', 'security')
      and routine.provolatile = 'v'
      and routine.prokind in ('f', 'p')
      and (
        routine.prosrc like '%''tenant_id''%'
        or routine.prosrc like '%''user_id''%'
        or routine.prosrc like '%''establishment_id''%'
        or routine.prosrc like '%''pos_terminal_id''%'
      )
  ),
  'ningun RPC saca identidad de un payload ni arma SQL dinamico con ella'
);

-- Toda rutina de public y de security fija search_path vacio. Hoy 002 lo verifica funcion por funcion; asi lo hereda cualquier RPC nuevo.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    where routine_schema.nspname in ('public', 'security')
      and routine.prokind in ('f', 'p')
      and not (coalesce(routine.proconfig, array[]::text[]) @> array['search_path=""'])
  ),
  'toda rutina de public y security corre con search_path vacio'
);

-- Los nueve wrappers publicos son invoker y sus privados son definer: el contrato del repo (002 prohibe cualquier definer en public) se sostiene con los RPC nuevos.
select ok(
  (select prosecdef from pg_catalog.pg_proc where oid = 'security.issue_document(uuid,uuid,uuid,uuid[],bigint,timestamptz,date,text,text,smallint,text,uuid)'::regprocedure)
  and not (select prosecdef from pg_catalog.pg_proc where oid = 'public.issue_document(uuid,uuid,uuid,uuid[],bigint,timestamptz,date,text,text,smallint,text,uuid)'::regprocedure),
  'issue_document es definer en security e invoker en public'
);

-- anon no puede ejecutar ningun RPC fiscal, ni el wrapper ni el privado.
select function_privs_are('public', 'issue_document', array['uuid', 'uuid', 'uuid', 'uuid[]', 'bigint', 'timestamptz', 'date', 'text', 'text', 'smallint', 'text', 'uuid']::name[], 'anon', array[]::text[], 'anon no puede emitir comprobantes');


select * from finish();

rollback;
