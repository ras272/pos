begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- Core objects and data-model constraints.
select has_type('public', 'tenant_role', 'el enum tenant_role existe');

select results_eq(
  $$select enumlabel from pg_catalog.pg_enum where enumtypid = 'public.tenant_role'::regtype order by enumsortorder$$,
  array['owner'::name, 'admin'::name, 'member'::name],
  'tenant_role solo contiene owner, admin y member'
);

select has_table('public', 'tenants', 'existe public.tenants');
select has_table('public', 'tenant_memberships', 'existe public.tenant_memberships');
select has_table('public', 'establishments', 'existe public.establishments');
select has_schema('security', 'existe el schema privado security');
select has_table('security', 'tenant_bootstrap_audit', 'existe el audit privado de bootstrap');

select col_type_is('public', 'tenants', 'id', 'uuid', 'tenants.id usa UUID');
select col_type_is('public', 'tenant_memberships', 'id', 'uuid', 'tenant_memberships.id usa UUID');
select col_type_is('public', 'establishments', 'id', 'uuid', 'establishments.id usa UUID');
select col_not_null('public', 'tenant_memberships', 'tenant_id', 'tenant_memberships.tenant_id es obligatorio');
select col_not_null('public', 'establishments', 'tenant_id', 'establishments.tenant_id es obligatorio');

select col_not_null('public', 'tenants', 'created_at', 'tenants.created_at es obligatorio');
select col_not_null('public', 'tenants', 'updated_at', 'tenants.updated_at es obligatorio');
select col_not_null('public', 'tenant_memberships', 'created_at', 'tenant_memberships.created_at es obligatorio');
select col_not_null('public', 'tenant_memberships', 'updated_at', 'tenant_memberships.updated_at es obligatorio');
select col_not_null('public', 'establishments', 'created_at', 'establishments.created_at es obligatorio');
select col_not_null('public', 'establishments', 'updated_at', 'establishments.updated_at es obligatorio');

select has_fk('public', 'tenant_memberships', 'tenant_memberships tiene foreign keys');
select has_fk('public', 'establishments', 'establishments tiene foreign keys');
select has_index('public', 'tenant_memberships', 'tenant_memberships_user_id_idx', 'user_id tiene un índice de FK dedicado');

select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_class table_class on table_class.oid = fk.conrelid
    join pg_catalog.pg_namespace table_schema on table_schema.oid = table_class.relnamespace
    where fk.contype = 'f'
      and table_schema.nspname = 'public'
      and not exists (
        select 1
        from pg_catalog.pg_index index_class
        where index_class.indrelid = fk.conrelid
          and index_class.indisvalid
          and array(
            select indexed_column.attribute_number::smallint
            from unnest(index_class.indkey::smallint[]) with ordinality as indexed_column(attribute_number, ordinal)
            where indexed_column.ordinal <= array_length(fk.conkey, 1)
            order by indexed_column.ordinal
          ) = fk.conkey
      )
  ),
  'cada foreign key pública tiene un índice cuyo prefijo coincide con la FK'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.tenant_memberships'::regclass
      and c.contype = 'u'
      and c.conkey = array[
        (select attnum from pg_catalog.pg_attribute where attrelid = 'public.tenant_memberships'::regclass and attname = 'tenant_id'),
        (select attnum from pg_catalog.pg_attribute where attrelid = 'public.tenant_memberships'::regclass and attname = 'user_id')
      ]::smallint[]
  ),
  'tenant_memberships es único por tenant y usuario'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.establishments'::regclass
      and c.contype = 'u'
      and c.conkey = array[
        (select attnum from pg_catalog.pg_attribute where attrelid = 'public.establishments'::regclass and attname = 'tenant_id'),
        (select attnum from pg_catalog.pg_attribute where attrelid = 'public.establishments'::regclass and attname = 'name')
      ]::smallint[]
  ),
  'establishments es único por tenant y nombre'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.tenants'::regclass
      and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%status%'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.tenant_memberships'::regclass
      and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%status%'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.establishments'::regclass
      and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%status%'
  ),
  'cada tabla con estado tiene una restricción de status'
);

-- RLS must be forced, with tenant IDs made immutable on every tenant-owned table.
select results_eq(
  $$select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid = 'public.tenants'::regclass$$,
  array[true],
  'RLS está habilitado y forzado en tenants'
);

select results_eq(
  $$select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid = 'public.tenant_memberships'::regclass$$,
  array[true],
  'RLS está habilitado y forzado en tenant_memberships'
);

select results_eq(
  $$select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid = 'public.establishments'::regclass$$,
  array[true],
  'RLS está habilitado y forzado en establishments'
);

select results_eq(
  $$select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class where oid = 'security.tenant_bootstrap_audit'::regclass$$,
  array[true],
  'RLS está habilitado y forzado en el audit privado'
);

select has_trigger('public', 'tenant_memberships', 'tenant_memberships_tenant_id_immutable', 'tenant_memberships impide cambiar tenant_id');
select has_trigger('public', 'establishments', 'establishments_tenant_id_immutable', 'establishments impide cambiar tenant_id');
select has_trigger('security', 'tenant_bootstrap_audit', 'tenant_bootstrap_audit_append_only', 'el audit privado es append-only');

select policies_are(
  'public',
  'tenants',
  array['tenants_select_active_members', 'tenants_update_active_admins'],
  'tenants tiene solo policies de lectura y actualización necesarias'
);

select policies_are(
  'public',
  'tenant_memberships',
  array[]::name[],
  'tenant_memberships no admite policies de mutación directa'
);

select policies_are(
  'public',
  'establishments',
  array['establishments_select_active_members', 'establishments_insert_active_admins', 'establishments_update_active_admins'],
  'establishments tiene policies por operación permitida'
);

select policies_are(
  'security',
  'tenant_bootstrap_audit',
  array[]::name[],
  'el audit privado no tiene policies de acceso de cliente'
);

-- Exact grants prevent privilege escalation before RLS gets a chance to decide.
select table_privs_are('public', 'tenants', 'authenticated', array['SELECT', 'UPDATE']::text[], 'authenticated solo recibe SELECT/UPDATE en tenants');
select table_privs_are('public', 'tenant_memberships', 'authenticated', array[]::text[], 'authenticated no recibe acceso directo a tenant_memberships');
select table_privs_are('public', 'establishments', 'authenticated', array['SELECT', 'INSERT', 'UPDATE']::text[], 'authenticated solo recibe SELECT/INSERT/UPDATE en establishments');
select table_privs_are('public', 'tenants', 'anon', array[]::text[], 'anon no recibe acceso a tenants');
select table_privs_are('public', 'tenant_memberships', 'anon', array[]::text[], 'anon no recibe acceso a tenant_memberships');
select table_privs_are('public', 'establishments', 'anon', array[]::text[], 'anon no recibe acceso a establishments');
select table_privs_are('security', 'tenant_bootstrap_audit', 'authenticated', array[]::text[], 'authenticated no recibe acceso al audit privado');
select table_privs_are('security', 'tenant_bootstrap_audit', 'anon', array[]::text[], 'anon no recibe acceso al audit privado');
select has_index('security', 'tenant_bootstrap_audit', 'tenant_bootstrap_audit_actor_id_created_at_idx', array['actor_id', 'created_at'], 'el audit indexa actor y tiempo para cuota y FK');
select has_index('security', 'tenant_bootstrap_audit', 'tenant_bootstrap_audit_tenant_id_idx', 'tenant_id', 'el audit indexa la FK de tenant');
select has_index('security', 'tenant_bootstrap_audit', 'tenant_bootstrap_audit_establishment_id_idx', 'establishment_id', 'el audit indexa la FK de establecimiento');

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class c
    cross join lateral pg_catalog.aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    where c.oid in ('public.tenants'::regclass, 'public.tenant_memberships'::regclass, 'public.establishments'::regclass)
      and acl.grantee = 0
  ),
  'PUBLIC no recibe privilegios de tablas de tenant'
);

select ok(
  not has_table_privilege('authenticated', 'public.tenants', 'delete')
  and not has_table_privilege('authenticated', 'public.tenants', 'truncate')
  and not has_table_privilege('authenticated', 'public.tenant_memberships', 'delete')
  and not has_table_privilege('authenticated', 'public.tenant_memberships', 'truncate')
  and not has_table_privilege('authenticated', 'public.establishments', 'delete')
  and not has_table_privilege('authenticated', 'public.establishments', 'truncate'),
  'authenticated no recibe DELETE ni TRUNCATE sobre datos de tenant'
);

select ok(
  not has_table_privilege('authenticated', 'security.tenant_bootstrap_audit', 'insert')
  and not has_table_privilege('authenticated', 'security.tenant_bootstrap_audit', 'update')
  and not has_table_privilege('authenticated', 'security.tenant_bootstrap_audit', 'delete')
  and not has_table_privilege('authenticated', 'security.tenant_bootstrap_audit', 'truncate'),
  'authenticated no puede mutar el audit append-only'
);

select schema_privs_are('public', 'authenticated', array['USAGE']::text[], 'authenticated solo usa el schema público');
select schema_privs_are('security', 'authenticated', array['USAGE']::text[], 'authenticated solo usa security para helpers necesarios');
select schema_privs_are('public', 'anon', array[]::text[], 'anon no puede usar el schema público');
select schema_privs_are('security', 'anon', array[]::text[], 'anon no puede usar el schema security');

select ok(
  not exists (
    select 1
    from pg_catalog.pg_default_acl default_acl
    left join pg_catalog.pg_namespace default_schema on default_schema.oid = default_acl.defaclnamespace
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) acl
    where default_acl.defaclrole = 'postgres'::regrole
      and (default_schema.nspname is null or default_schema.nspname in ('public', 'security'))
      and acl.grantee in (0, 'anon'::regrole, 'authenticated'::regrole)
  ),
  'los defaults no otorgan privilegios de schema, tabla, secuencia, tipo ni rutina a PUBLIC, anon o authenticated'
);

-- Function and type defaults otherwise fall back to PUBLIC when no explicit
-- pg_default_acl row exists. Use a throwaway schema to verify the effective
-- global defaults for the postgres migration owner, not only catalog entries.
create schema default_privilege_probe;

create type default_privilege_probe.probe_role as enum ('probe');

create function default_privilege_probe.probe_function()
returns boolean
language sql
as $$
  select true;
$$;

select ok(
  not has_type_privilege('anon', 'default_privilege_probe.probe_role', 'usage')
  and not has_type_privilege('authenticated', 'default_privilege_probe.probe_role', 'usage')
  and not exists (
    select 1
    from pg_catalog.pg_type type_class
    cross join lateral pg_catalog.aclexplode(coalesce(type_class.typacl, acldefault('T', type_class.typowner))) acl
    where type_class.oid = 'default_privilege_probe.probe_role'::regtype
      and acl.grantee = 0
  ),
  'los tipos futuros no reciben USAGE de PUBLIC, anon ni authenticated'
);

select ok(
  not has_function_privilege('anon', 'default_privilege_probe.probe_function()', 'execute')
  and not has_function_privilege('authenticated', 'default_privilege_probe.probe_function()', 'execute')
  and not exists (
    select 1
    from pg_catalog.pg_proc routine
    cross join lateral pg_catalog.aclexplode(coalesce(routine.proacl, acldefault('f', routine.proowner))) acl
    where routine.oid = 'default_privilege_probe.probe_function()'::regprocedure
      and acl.grantee = 0
  ),
  'las rutinas futuras no reciben EXECUTE de PUBLIC, anon ni authenticated'
);

-- Definer helpers are private, deterministic, qualified and only exposed through
-- the invoker wrapper that forms the public RPC contract.
select has_function('security', 'is_tenant_member', array['uuid', 'tenant_role[]']::name[], 'existe el helper de membresía');
select has_function('security', 'bootstrap_tenant', array['text', 'text']::name[], 'existe el bootstrap privado');
select has_function('public', 'bootstrap_tenant', array['text', 'text']::name[], 'existe el wrapper público de bootstrap');

select function_privs_are('public', 'bootstrap_tenant', array['text', 'text']::name[], 'authenticated', array['EXECUTE']::text[], 'authenticated puede ejecutar solo el wrapper público');
select function_privs_are('public', 'bootstrap_tenant', array['text', 'text']::name[], 'anon', array[]::text[], 'anon no puede ejecutar el wrapper público');
select function_privs_are('security', 'is_tenant_member', array['uuid', 'tenant_role[]']::name[], 'authenticated', array['EXECUTE']::text[], 'authenticated puede usar el helper RLS mínimo');
select function_privs_are('security', 'is_tenant_member', array['uuid', 'tenant_role[]']::name[], 'anon', array[]::text[], 'anon no puede ejecutar el helper RLS');
select function_privs_are('security', 'bootstrap_tenant', array['text', 'text']::name[], 'authenticated', array['EXECUTE']::text[], 'el wrapper invoker recibe el grant mínimo para delegar al bootstrap privado');
select function_privs_are('security', 'bootstrap_tenant', array['text', 'text']::name[], 'anon', array[]::text[], 'anon no puede ejecutar el bootstrap privado');

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid in (
      'security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure,
      'security.bootstrap_tenant(text,text)'::regprocedure,
      'public.bootstrap_tenant(text,text)'::regprocedure
    )
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  'ninguna rutina de tenant concede EXECUTE a PUBLIC'
);

select ok(
  (select prosecdef from pg_catalog.pg_proc where oid = 'security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure)
  and (select provolatile = 's' from pg_catalog.pg_proc where oid = 'security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure)
  and (select proconfig @> array['search_path=""'] from pg_catalog.pg_proc where oid = 'security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure),
  'el helper de membresía es STABLE SECURITY DEFINER con search_path vacío'
);

select ok(
  (select prosecdef from pg_catalog.pg_proc where oid = 'security.bootstrap_tenant(text,text)'::regprocedure)
  and (select proconfig @> array['search_path=""'] from pg_catalog.pg_proc where oid = 'security.bootstrap_tenant(text,text)'::regprocedure)
  and not (select prosecdef from pg_catalog.pg_proc where oid = 'public.bootstrap_tenant(text,text)'::regprocedure),
  'el bootstrap privado es definer y el wrapper público es invoker'
);

select ok(
  (select pg_catalog.pg_get_functiondef('security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure) like '%auth.uid()%')
  and (select pg_catalog.pg_get_functiondef('security.bootstrap_tenant(text,text)'::regprocedure) like '%auth.uid()%')
  and (select pg_catalog.pg_get_functiondef('security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure) not ilike '%metadata%')
  and (select pg_catalog.pg_get_functiondef('security.bootstrap_tenant(text,text)'::regprocedure) not ilike '%metadata%')
  and (select pg_catalog.pg_get_functiondef('security.is_tenant_member(uuid,public.tenant_role[])'::regprocedure) not ilike '%execute%')
  and (select pg_catalog.pg_get_functiondef('security.bootstrap_tenant(text,text)'::regprocedure) not ilike '%execute%'),
  'los helpers derivan auth.uid y no usan metadata JWT ni SQL dinámico'
);

select ok(
  (select pg_catalog.pg_get_functiondef('security.bootstrap_tenant(text,text)'::regprocedure) like '%pg_advisory_xact_lock%')
  and (select pg_catalog.pg_get_functiondef('security.bootstrap_tenant(text,text)'::regprocedure) like '%tenant_bootstrap_audit%')
  and exists (
    select 1
    from pg_catalog.pg_index index_class
    where index_class.indexrelid = 'security.tenant_bootstrap_audit_actor_id_created_at_idx'::regclass
  ),
  'el bootstrap usa lock transaccional y el índice actor/tiempo para la cuota anti-burst'
);

select is(
  (select proargnames[1:pronargs] from pg_catalog.pg_proc where oid = 'security.bootstrap_tenant(text,text)'::regprocedure),
  array['p_tenant_name', 'p_establishment_name']::text[],
  'el bootstrap privado no acepta parámetros de usuario ni rol'
);

select is(
  (select proargnames[1:pronargs] from pg_catalog.pg_proc where oid = 'public.bootstrap_tenant(text,text)'::regprocedure),
  array['p_tenant_name', 'p_establishment_name']::text[],
  'el wrapper público no acepta parámetros de usuario ni rol'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  )
  and not exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('v', 'm')
  ),
  'public no expone helpers SECURITY DEFINER ni vistas inseguras'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_db_role_setting s
    cross join lateral unnest(s.setconfig) setting
    cross join lateral unnest(
      pg_catalog.string_to_array(
        pg_catalog.substr(setting, pg_catalog.length('pgrst.db_schemas=') + 1),
        ','
      )
    ) configured_schema
    where s.setrole in (0, 'authenticator'::regrole)
      and s.setdatabase in (
        0,
        (select oid from pg_catalog.pg_database where datname = pg_catalog.current_database())
      )
      and setting like 'pgrst.db_schemas=%'
      and pg_catalog.btrim(configured_schema) = 'security'
  ),
  'ningún override de rol o base de PostgREST expone security por Data API'
);

-- Aserciones de catálogo. Las de arriba enumeran objetos por nombre y solo
-- cubren lo que alguien se acordó de agregar; estas recorren el catálogo, así
-- que una tabla nueva que no cumpla rompe el CI sola, sin que nadie las toque.

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'security')
      and c.relkind = 'r'
      and not (c.relrowsecurity and c.relforcerowsecurity)
  ),
  'toda tabla de public y security tiene RLS habilitada y forzada'
);

-- Un índice parcial satisface el escaneo de prefijo de más arriba sin servir al
-- ON DELETE ni al join: la FK necesita uno completo.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_class table_class on table_class.oid = fk.conrelid
    join pg_catalog.pg_namespace table_schema on table_schema.oid = table_class.relnamespace
    where fk.contype = 'f'
      and table_schema.nspname = 'public'
      and not exists (
        select 1
        from pg_catalog.pg_index index_class
        where index_class.indrelid = fk.conrelid
          and index_class.indisvalid
          and index_class.indpred is null
          and array(
            select indexed_column.attribute_number::smallint
            from unnest(index_class.indkey::smallint[]) with ordinality as indexed_column(attribute_number, ordinal)
            where indexed_column.ordinal <= array_length(fk.conkey, 1)
            order by indexed_column.ordinal
          ) = fk.conkey
      )
  ),
  'cada foreign key pública tiene un índice completo, no solamente parcial'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid = a.attrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and a.attname = 'tenant_id'
      and not a.attisdropped
      and not exists (
        select 1
        from pg_catalog.pg_trigger t
        where t.tgrelid = c.oid
          and not t.tgisinternal
          and t.tgfoid = 'security.prevent_tenant_id_change()'::regprocedure
      )
  ),
  'toda tabla pública con tenant_id impide moverlo de tenant con un trigger'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute a
    join pg_catalog.pg_class c on c.oid = a.attrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and a.attname = 'updated_at'
      and not a.attisdropped
      and not exists (
        select 1
        from pg_catalog.pg_trigger t
        where t.tgrelid = c.oid
          and not t.tgisinternal
          and t.tgfoid = 'security.set_updated_at()'::regprocedure
      )
  ),
  'toda tabla pública con updated_at lo mantiene con un trigger'
);

-- El dominio archiva con status; el borrado físico no se expone a un cliente.
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants g
    where g.table_schema in ('public', 'security')
      and g.grantee in ('anon', 'authenticated')
      and g.privilege_type in ('DELETE', 'TRUNCATE')
  ),
  'ningún rol de cliente recibe DELETE ni TRUNCATE'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'security')
      and pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE')
  ),
  'ninguna función de public o security queda ejecutable por PUBLIC'
);

-- El cuerpo de un SECURITY DEFINER corre como postgres, que tiene BYPASSRLS:
-- adentro no hay policy que lo frene. La unica defensa es que la funcion
-- verifique membresia por su cuenta, y esta asercion es lo que impide que esa
-- regla quede en la disciplina de quien escriba el proximo RPC.
--
-- Se filtra por volatil porque ese es exactamente el conjunto que puede
-- escribir: Postgres prohibe INSERT, UPDATE y DELETE dentro de una funcion que
-- no lo sea. Y se lee prosrc, el cuerpo, no la definicion completa: si se
-- leyera la cabecera, una funcion llamada is_tenant_member_algo pasaria sola.
--
-- bootstrap_tenant es la unica excepcion legitima: crea el tenant, asi que no
-- puede exigir una membresia que todavia no existe.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    where routine_schema.nspname = 'security'
      and routine.prosecdef
      and routine.provolatile = 'v'
      and routine.prokind in ('f', 'p')
      and routine.prorettype <> 'pg_catalog.trigger'::regtype
      and routine.oid <> 'security.bootstrap_tenant(text,text)'::regprocedure
      and (
        -- `not security.is_tenant_member` cubre las dos formas en uso:
        -- `if not ...` y `if v_tenant_id is null or not ...`, que ademas
        -- rechaza la fila inexistente. Lo que no cubre es la ausencia de
        -- verificacion, que es lo unico que se quiere prohibir.
        routine.prosrc not like '%not security.is_tenant_member%'
        or routine.prosrc not like '%42501%'
      )
  ),
  'todo RPC de escritura de security verifica membresia y rechaza con 42501'
);

-- Ninguna funcion expuesta al Data API puede ser definer: los privilegiados
-- viven en security, y en public solo quedan wrappers que delegan.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc routine
    join pg_catalog.pg_namespace routine_schema on routine_schema.oid = routine.pronamespace
    where routine_schema.nspname = 'public'
      and routine.prosecdef
  ),
  'ninguna funcion de public es SECURITY DEFINER'
);

select * from finish();
rollback;
