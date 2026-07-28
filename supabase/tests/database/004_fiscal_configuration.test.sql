begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- Fixtures como dueno de la base. Lo estructural y las reglas del negocio
-- corren asi; el aislamiento por RLS lo cubren 003 y 005.
insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'owner-b@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'member-a@example.test');

insert into public.tenants (id, name, status)
values
  ('10000000-0000-0000-0000-000000000001', 'Tenant A', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'Tenant B', 'active');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active');

insert into public.establishments (id, tenant_id, name, establishment_code, status)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local A', '001', 'active'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Local B', '001', 'active'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'Local A dos', '002', 'active');

insert into public.pos_terminals (id, tenant_id, establishment_id, name, expedition_point_code, order_code_prefix, status)
values
  ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Caja 1', '001', 'C1', 'active'),
  ('80000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Caja B', '001', 'B1', 'active');

insert into public.fiscal_timbrados (id, tenant_id, number, valid_from, valid_to, status)
values
  ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '12345678', date '2026-01-01', date '2026-12-31', 'active'),
  ('90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '87654321', date '2026-01-01', date '2026-12-31', 'active'),
  ('90000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '11112222', date '2025-01-01', date '2025-12-31', 'expired');

insert into public.fiscal_thresholds (id, tenant_id, anonymous_buyer_threshold_gs, effective_from, effective_to, status)
values
  ('d0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 35000000, date '2026-01-01', null, 'active');

insert into public.document_counters (id, tenant_id, establishment_id, pos_terminal_id, timbrado_id, document_type, range_from, range_to, last_number, status)
values
  ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 1, 1000, 990, 'active');

insert into public.customers (id, tenant_id, doc_type, doc_number, name, status)
values
  ('c0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'CI', '1234567', 'Cliente mostrador', 'active');

-- MARCADOR_CUERPO
-- El create table compila: hay exactamente un check llamado document_counters_last_number_check, no dos con el mismo nombre en la misma relación.
select is(
  (
    select pg_catalog.count(*)::int
    from pg_catalog.pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.document_counters'::regclass
      and constraint_row.contype = 'c'
      and constraint_row.conname = 'document_counters_last_number_check'
  ),
  1,
  'document_counters tiene un solo check de last_number y su nombre es único en la relación'
);

-- Ningún nombre de constraint del schema público llegó al truncado silencioso de 63 caracteres.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint as constraint_row
    join pg_catalog.pg_class as table_class on table_class.oid = constraint_row.conrelid
    join pg_catalog.pg_namespace as table_schema on table_schema.oid = table_class.relnamespace
    where table_schema.nspname = 'public'
      and pg_catalog.char_length(constraint_row.conname::text) >= 63
  ),
  'ningún nombre de constraint del schema público llegó al límite de 63 caracteres que Postgres trunca en silencio'
);

-- Renovar el rango cierra la fila vigente sin tocar su last_number.
select lives_ok(
  $$update public.document_counters set status = 'closed' where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'el rango vigente se cierra sin reescribir su rango ni su último número'
);

-- Renovar el rango es una FILA NUEVA, no un update de la fila anterior.
select lives_ok(
  $$insert into public.document_counters (id, tenant_id, establishment_id, pos_terminal_id, timbrado_id, document_type, range_from, range_to) values ('a0000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 1001, 2000)$$,
  'el rango nuevo convive con el anterior en vez de pisarlo'
);

-- El rango cerrado conserva su último número emitido.
select is(
  (select last_number from public.document_counters where id = 'a0000000-0000-0000-0000-000000000001'),
  990::bigint,
  'el rango cerrado conserva el último número que emitió'
);

-- Un documento firmado offline bajo el rango anterior reconcilia contra la fila que CONTIENE su número, no contra la vigente.
select results_eq(
  $$update public.document_counters set last_number = greatest(last_number, 991) where pos_terminal_id = '80000000-0000-0000-0000-000000000001' and document_type = 'invoice' and timbrado_id = '90000000-0000-0000-0000-000000000001' and 991 between range_from and range_to returning id$$,
  array['a0000000-0000-0000-0000-000000000001'::uuid],
  'un documento que sincroniza dentro de las 72 h reconcilia contra la fila de SU rango, no contra la vigente'
);

-- El último número sigue acotado a su propio rango: 5000 no cabe en 1-1000.
select throws_ok(
  $$update public.document_counters set last_number = 5000 where id = 'a0000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'last_number no puede salirse del rango de su propia fila'
);

-- Hay un solo rango vigente por punto de expedición y tipo de documento.
select throws_ok(
  $$insert into public.document_counters (tenant_id, establishment_id, pos_terminal_id, timbrado_id, document_type, range_from, range_to) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 5001, 6000)$$,
  '23505',
  null,
  'dos rangos vigentes a la vez en la misma caja y tipo de documento son imposibles'
);

-- Un rango asignado no se puede reescribir después.
select throws_ok(
  $$update public.document_counters set range_to = 9999999 where id = 'a0000000-0000-0000-0000-000000000002'$$,
  'P0001',
  'authorized number range is immutable',
  'el rango autorizado es inmutable después de asignado'
);

-- El correlativo no retrocede.
select throws_ok(
  $$update public.document_counters set last_number = 100 where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'document counter cannot go backwards',
  'el contador de un rango solo avanza'
);

-- Un rango cerrado no se reabre.
select throws_ok(
  $$update public.document_counters set status = 'active' where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'a closed number range cannot be reopened',
  'un rango cerrado no vuelve a estar vigente'
);

-- Los RPC derivan el actor de auth.uid(), asi que a partir de aca se entra como
-- cliente real y no como dueno de la base.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- assign_number_range rechaza un rango que se solapa con otro ya asignado bajo el mismo timbrado.
select throws_ok(
  $$select public.assign_number_range('80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 1500, 2500)$$,
  'P0001',
  'number range overlaps an existing range',
  'dos rangos solapados harían ambigua la reconciliación por número'
);

-- assign_number_range rechaza un timbrado que no está vigente.
select throws_ok(
  $$select public.assign_number_range('80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000003', 'invoice', 3001, 4000)$$,
  'P0001',
  'fiscal stamp is not active',
  'no se asigna rango bajo un timbrado revocado o vencido'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- Un member no puede asignar rangos: dar de alta numeración es acto fiscal.
select throws_ok(
  $$select public.assign_number_range('80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 3001, 4000)$$,
  '42501',
  'not authorized to assign a number range',
  'un member no puede asignar un rango de numeración'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- El tenant sale de la fila del terminal, no del parámetro: el owner de A no puede asignar rango a una caja de B.
select throws_ok(
  $$select public.assign_number_range('80000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000001', 'invoice', 1, 1000)$$,
  '42501',
  'not authorized to assign a number range',
  'el owner del tenant A no puede asignar un rango al punto de expedición del tenant B'
);

reset role;

-- Los triggers de inmutabilidad disparan sin importar el rol, asi que estas
-- corren como dueno: si entraran como cliente, RLS filtraria la fila antes y el
-- update devolveria cero filas en vez de levantar el error que se quiere probar.

-- El código del punto de expedición es inmutable.
select throws_ok(
  $$update public.pos_terminals set expedition_point_code = '002' where id = '80000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'expedition point code is immutable',
  'el código del punto de expedición no se puede editar después del alta'
);

-- El punto de expedición no se muda de local.
select throws_ok(
  $$update public.pos_terminals set establishment_id = '20000000-0000-0000-0000-000000000003' where id = '80000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'expedition point establishment is immutable',
  'un punto de expedición no cambia de establecimiento'
);

-- Archivar una caja no libera su código de punto de expedición: el correlativo no se parte en dos.
select throws_ok(
  $$insert into public.pos_terminals (tenant_id, establishment_id, name, expedition_point_code, order_code_prefix) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Caja 1 nueva', '001', 'B')$$,
  '23505',
  null,
  'el código de punto de expedición es único por local aun contra filas archivadas'
);

-- El código fiscal del establecimiento es inmutable una vez cargado.
select throws_ok(
  $$update public.establishments set establishment_code = '002' where id = '20000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'establishment code is immutable',
  'el código de establecimiento no se puede corregir después de cargado'
);

-- El número del timbrado es inmutable.
select throws_ok(
  $$update public.fiscal_timbrados set number = '87654321' where id = '90000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'fiscal stamp number is immutable',
  'el número de timbrado no se edita después del alta'
);

-- La vigencia del timbrado queda congelada en la fuente.
select throws_ok(
  $$update public.fiscal_timbrados set valid_to = date '2099-12-31' where id = '90000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'fiscal stamp validity is immutable',
  'la vigencia del timbrado es inmutable: extenderla revalidaría comprobantes ya emitidos'
);

-- Un timbrado revocado no vuelve a estar activo.
select throws_ok(
  $$update public.fiscal_timbrados set status = 'active' where id = '90000000-0000-0000-0000-000000000003'$$,
  'P0001',
  'fiscal stamp cannot return to active',
  'un timbrado vencido o revocado no se puede reactivar'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

-- El umbral innominado no se escribe directo desde el cliente.
select throws_ok(
  $$insert into public.fiscal_thresholds (tenant_id, anonymous_buyer_threshold_gs, effective_from) values ('10000000-0000-0000-0000-000000000001', 1, date '2030-01-01')$$,
  '42501',
  null,
  'ningún cliente puede insertar una vigencia de umbral: entra solo por RPC'
);

-- Las vigencias del umbral solo avanzan: una retroactiva se rechaza.
select throws_ok(
  $$select public.set_fiscal_threshold('20000000-0000-0000-0000-000000000001', 20000000, date '2024-01-01')$$,
  '22023',
  'fiscal threshold periods must move forward',
  'una vigencia retroactiva del umbral se rechaza: solaparía dos períodos'
);

-- El decreto que bajo el umbral de 35M a 7M entra como una vigencia nueva.
select lives_ok(
  $$select public.set_fiscal_threshold('20000000-0000-0000-0000-000000000001', 7000000, date '2026-07-01')$$,
  'un owner puede fijar la vigencia nueva del umbral innominado'
);

reset role;

-- Fijar un umbral nuevo cierra el anterior: nunca hay dos vigencias abiertas.
select is(
  (
    select pg_catalog.count(*)::int
    from public.fiscal_thresholds as threshold
    where threshold.tenant_id = '10000000-0000-0000-0000-000000000001'
      and threshold.effective_to is null
  ),
  1,
  'después de fijar un umbral nuevo queda exactamente una vigencia abierta'
);

-- El umbral se resuelve por la fecha de la VENTA, no por la de hoy, y la resolución devuelve una sola fila.
select is(
  (
    select threshold.anonymous_buyer_threshold_gs::bigint
    from public.fiscal_thresholds as threshold
    where threshold.tenant_id = '10000000-0000-0000-0000-000000000001'
      and threshold.effective_from <= date '2026-06-30'
      and (threshold.effective_to is null or threshold.effective_to > date '2026-06-30')
  ),
  35000000::bigint,
  'una venta del 30-jun resuelve el umbral vigente ese día, no el de hoy, y matchea una sola fila'
);

-- La venta del día siguiente al decreto resuelve el umbral nuevo: los intervalos son contiguos y semiabiertos.
select is(
  (
    select threshold.anonymous_buyer_threshold_gs::bigint
    from public.fiscal_thresholds as threshold
    where threshold.tenant_id = '10000000-0000-0000-0000-000000000001'
      and threshold.effective_from <= date '2026-07-01'
      and (threshold.effective_to is null or threshold.effective_to > date '2026-07-01')
  ),
  7000000::bigint,
  'el primer día de la vigencia nueva ya resuelve el umbral nuevo, sin hueco ni solape'
);

-- 'vigente' y 'sin fecha de cierre' no pueden contradecirse.
select throws_ok(
  $$insert into public.fiscal_thresholds (tenant_id, anonymous_buyer_threshold_gs, effective_from, effective_to, status) values ('10000000-0000-0000-0000-000000000002', 7000000, date '2026-01-01', date '2026-06-01', 'active')$$,
  '23514',
  null,
  'una vigencia con fecha de cierre no puede seguir marcada como activa'
);

-- Un monto ni una fecha de inicio de umbral se editan después: la auditoría tiene que ser reproducible.
select throws_ok(
  $$update public.fiscal_thresholds set anonymous_buyer_threshold_gs = 1 where id = 'd0000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'fiscal threshold amount and start date are immutable',
  'el monto de una vigencia de umbral ya escrita no se puede cambiar'
);

-- fiscal_certificates no tiene ninguna columna capaz de guardar material de clave, ni la puede tener mañana.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute as column_row
    where column_row.attrelid = 'public.fiscal_certificates'::regclass
      and column_row.attnum > 0
      and not column_row.attisdropped
      and column_row.attname::text ~ '(certificate|p12|pfx|private|key|password|passphrase|secret)'
  ),
  'fiscal_certificates no tiene ninguna columna capaz de guardar un .p12, una contraseña ni material de clave'
);

-- El nombre explícito de las columnas prohibidas también se verifica, para que el fallo se lea claro.
select hasnt_column('public', 'fiscal_certificates', 'private_key', 'fiscal_certificates no guarda la clave privada del F1');

-- Un contador no puede colgar del punto de expedición de otro tenant.
select throws_ok(
  $$insert into public.document_counters (tenant_id, establishment_id, pos_terminal_id, timbrado_id, document_type, range_from, range_to) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000002', '90000000-0000-0000-0000-000000000001', 'invoice', 1, 1000)$$,
  '23503',
  null,
  'un contador no puede referenciar una caja de otro establecimiento ni de otro tenant'
);

-- Un contador no puede usar el timbrado de otro tenant.
select throws_ok(
  $$insert into public.document_counters (tenant_id, establishment_id, pos_terminal_id, timbrado_id, document_type, range_from, range_to) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002', 'credit_note', 1, 1000)$$,
  '23503',
  null,
  'un contador no puede colgar de un timbrado de otro tenant'
);

-- El cajero (member) puede dar de alta un cliente en el momento del cobro sobre el umbral.
select lives_ok(
  $$insert into public.customers (tenant_id, doc_type, doc_number, ruc_dv, name) values ('10000000-0000-0000-0000-000000000001', 'RUC', '80012345', 7, 'Empresa Cliente SA')$$,
  'un member puede crear un cliente sin trabar la caja'
);

-- Un CI no lleva dígito verificador y un RUC sí.
select throws_ok(
  $$insert into public.customers (tenant_id, doc_type, doc_number, ruc_dv, name) values ('10000000-0000-0000-0000-000000000001', 'CI', '4123456', 3, 'Cliente con DV inventado')$$,
  '23514',
  null,
  'una cédula no puede llevar dígito verificador de RUC'
);

-- El documento de un cliente es único por tenant, incluso contra filas archivadas.
select throws_ok(
  $$insert into public.customers (tenant_id, doc_type, doc_number, ruc_dv, name) values ('10000000-0000-0000-0000-000000000001', 'RUC', '80012345', 7, 'Duplicado')$$,
  '23505',
  null,
  'no puede haber dos clientes con el mismo documento en un tenant'
);

-- El cliente solo lee los contadores: el alta y la renovación de rango van por RPC.
select table_privs_are('public', 'document_counters', 'authenticated', array['SELECT']::text[], 'authenticated solo recibe SELECT sobre document_counters');

-- El cliente solo lee el umbral: se fija por RPC.
select table_privs_are('public', 'fiscal_thresholds', 'authenticated', array['SELECT']::text[], 'authenticated solo recibe SELECT sobre fiscal_thresholds');

-- La denegación de escritura del contador es la AUSENCIA de policy, igual que tenant_memberships en la fundación.
select policies_are('public', 'document_counters', array['document_counters_select_active_members'], 'document_counters solo tiene policy de lectura');

-- Lo mismo para el umbral.
select policies_are('public', 'fiscal_thresholds', array['fiscal_thresholds_select_active_members'], 'fiscal_thresholds solo tiene policy de lectura');

-- Las tablas de configuración fiscal sí tienen sus tres policies por operación.
select policies_are('public', 'pos_terminals', array['pos_terminals_select_active_members', 'pos_terminals_insert_active_admins', 'pos_terminals_update_active_admins'], 'pos_terminals tiene una policy por operación permitida');

-- anon no alcanza ninguna tabla de la capa fiscal.
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants as grant_row
    where grant_row.table_schema = 'public'
      and grant_row.grantee = 'anon'
      and grant_row.table_name in ('pos_terminals', 'fiscal_timbrados', 'fiscal_thresholds', 'fiscal_certificates', 'document_counters', 'customers')
  ),
  'anon no recibe ningún privilegio sobre las tablas de configuración fiscal'
);

-- Los RPC de la capa no aceptan tenant_id, user_id ni rol como parámetro de identidad.
select is(
  (select proargnames[1:pronargs] from pg_catalog.pg_proc where oid = 'public.assign_number_range(uuid,uuid,text,bigint,bigint)'::regprocedure),
  array['p_pos_terminal_id', 'p_timbrado_id', 'p_document_type', 'p_range_from', 'p_range_to']::text[],
  'assign_number_range no acepta tenant_id ni user_id: el tenant se deriva de la fila del terminal'
);

-- Todo RPC definer de la capa verifica membresía antes de escribir.
select ok(
  (select pg_catalog.pg_get_functiondef('security.assign_number_range(uuid,uuid,text,bigint,bigint)'::regprocedure) like '%is_tenant_member%')
  and (select pg_catalog.pg_get_functiondef('security.set_fiscal_threshold(uuid,bigint,date)'::regprocedure) like '%is_tenant_member%')
  and (select proconfig @> array['search_path=""'] from pg_catalog.pg_proc where oid = 'security.assign_number_range(uuid,uuid,text,bigint,bigint)'::regprocedure)
  and (select proconfig @> array['search_path=""'] from pg_catalog.pg_proc where oid = 'security.set_fiscal_threshold(uuid,bigint,date)'::regprocedure),
  'los RPC definer de la capa fiscal verifican membresía y corren con search_path vacío'
);

-- La capa fiscal no le devolvió a la fundación ningún grant que le hubiera arrancado un revoke masivo.
select table_privs_are('public', 'establishments', 'authenticated', array['SELECT', 'INSERT', 'UPDATE']::text[], 'la migración fiscal no le quitó a authenticated los grants de la fundación sobre establishments');

-- RLS habilitada y forzada en las seis tablas nuevas.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as table_class
    where table_class.oid in (
      'public.pos_terminals'::regclass,
      'public.fiscal_timbrados'::regclass,
      'public.fiscal_thresholds'::regclass,
      'public.fiscal_certificates'::regclass,
      'public.document_counters'::regclass,
      'public.customers'::regclass
    )
      and not (table_class.relrowsecurity and table_class.relforcerowsecurity)
  ),
  'las seis tablas de la capa fiscal tienen RLS habilitada y forzada'
);

-- El índice de la reconciliación y el de la vigencia existen con las columnas exactas.
select has_index('public', 'document_counters', 'document_counters_active_range_uidx', 'hay un índice único parcial que garantiza un solo rango vigente por caja y tipo');


select * from finish();

rollback;
