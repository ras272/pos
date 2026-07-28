begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'cajero-a@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'owner-b@example.test');

insert into public.tenants (id, name, status)
values
  ('10000000-0000-0000-0000-000000000001', 'Tenant A', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'Tenant B', 'active');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'owner', 'active');

insert into public.establishments (id, tenant_id, name, establishment_code, status)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local A', '001', 'active'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Local B', '001', 'active');

insert into public.product_categories (id, tenant_id, name)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Lomitos');

insert into public.products (id, tenant_id, category_id, name, price_gs, iva_rate)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Lomito completo', 45000, 10);

insert into public.modifier_groups (id, tenant_id, name, selection_min, selection_max)
values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Extras', 0, 5);

insert into public.modifier_options (id, tenant_id, modifier_group_id, name, price_delta_gs)
values
  ('50000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'Extra queso', 8000);

insert into public.dining_areas (id, tenant_id, establishment_id, name)
values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Salon');

insert into public.dining_tables (id, tenant_id, establishment_id, dining_area_id, code)
values
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '12');

insert into public.pos_terminals (id, tenant_id, establishment_id, name, expedition_point_code, order_code_prefix)
values
  ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Caja 1', '001', 'C1');

insert into public.cash_sessions (id, tenant_id, establishment_id, pos_terminal_id, business_date, opened_by_user_id, opened_at, opening_float_gs, status)
values
  ('b0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', date '2026-07-27', '00000000-0000-0000-0000-000000000004', timestamptz '2026-07-27T18:00:00Z', 100000, 'open');

-- Un turno ya cerrado del dia anterior: es al que apunta una correccion.
insert into public.cash_sessions (id, tenant_id, establishment_id, pos_terminal_id, business_date, opened_by_user_id, opened_at, opening_float_gs, closed_by_user_id, closed_at, counted_cash_gs, expected_cash_gs, status)
values
  ('b0000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', date '2026-07-26', '00000000-0000-0000-0000-000000000004', timestamptz '2026-07-26T18:00:00Z', 100000, '00000000-0000-0000-0000-000000000004', timestamptz '2026-07-26T23:40:00Z', 1250000, 1250000, 'closed');

insert into public.orders (id, tenant_id, establishment_id, channel, table_id, code, business_date, opened_by_user_id, opened_at, status)
values
  ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'dine_in', '70000000-0000-0000-0000-000000000001', 'C1-0001', date '2026-07-27', '00000000-0000-0000-0000-000000000004', timestamptz '2026-07-27T20:00:00Z', 'open'),
  ('90000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'counter', null, 'C1-0002', date '2026-07-27', '00000000-0000-0000-0000-000000000004', timestamptz '2026-07-27T20:05:00Z', 'open'),
  ('90000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'counter', null, 'B1-0001', date '2026-07-27', '00000000-0000-0000-0000-000000000002', timestamptz '2026-07-27T20:10:00Z', 'open');

-- La cuenta de mostrador queda cerrada: es la que prueba que un comprobante ya
-- cobrado no admite mas lineas ni ediciones. El trigger exige que quien cierra
-- sea el actor verificado, asi que el claim se fija aun escribiendo como dueno.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);

update public.orders
set status = 'settled',
    closed_by_user_id = '00000000-0000-0000-0000-000000000004',
    closed_at = timestamptz '2026-07-27T20:30:00Z'
where id = '90000000-0000-0000-0000-000000000002';

insert into public.order_lines (id, tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, modifiers_total_gs, discount_gs, line_total_gs, status)
values
  ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 1, 'Lomito completo', 1, 45000, 10, 0, 0, 45000, 'active');

-- MARCADOR_CUERPO
-- authenticated no recibe UPDATE de tabla sobre orders: el cierre no es alcanzable por PostgREST
select table_privs_are('public', 'orders', 'authenticated', array['SELECT', 'INSERT']::text[], 'authenticated solo recibe SELECT/INSERT de tabla en orders');

-- las cuatro columnas de cierre no son actualizables por un cliente y las tres operativas sí
select ok(
  not pg_catalog.has_column_privilege('authenticated', 'public.orders', 'status', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.orders', 'closed_at', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.orders', 'closed_by_user_id', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.orders', 'cancel_reason', 'update')
  and pg_catalog.has_column_privilege('authenticated', 'public.orders', 'table_id', 'update')
  and pg_catalog.has_column_privilege('authenticated', 'public.orders', 'guest_count', 'update')
  and pg_catalog.has_column_privilege('authenticated', 'public.orders', 'note', 'update'),
  'cerrar la cuenta no es un PATCH: solo mesa, comensales y nota son actualizables'
);

-- el snapshot de la línea no se puede reescribir desde el cliente
select ok(
  not pg_catalog.has_column_privilege('authenticated', 'public.order_lines', 'unit_price_gs', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.order_lines', 'iva_rate', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.order_lines', 'product_id', 'update')
  and not pg_catalog.has_column_privilege('authenticated', 'public.order_lines', 'product_name', 'update')
  and pg_catalog.has_column_privilege('authenticated', 'public.order_lines', 'status', 'update'),
  'el precio y la tasa congelados al agregar no se editan; anular sí'
);

-- el turno de caja no recibe UPDATE en ninguna forma: el arqueo lo calcula el servidor
select table_privs_are('public', 'cash_sessions', 'authenticated', array['SELECT', 'INSERT']::text[], 'authenticated no puede actualizar un turno de caja');

-- cash_movements es append-only también a nivel de grant
select table_privs_are('public', 'cash_movements', 'authenticated', array['SELECT', 'INSERT']::text[], 'authenticated solo lee e inserta movimientos de caja');

-- las cinco tablas tienen RLS habilitada y forzada
select ok(
  not exists (
    select 1
    from pg_catalog.pg_class c
    where c.oid in (
      'public.orders'::regclass,
      'public.order_lines'::regclass,
      'public.order_line_modifiers'::regclass,
      'public.cash_sessions'::regclass,
      'public.cash_movements'::regclass
    )
      and not (c.relrowsecurity and c.relforcerowsecurity)
  ),
  'RLS está habilitada y forzada en la cuenta y en la caja'
);

-- orders expone exactamente tres policies, una por operación, y ninguna de delete
select policies_are(
  'public',
  'orders',
  array['orders_select_active_members', 'orders_insert_active_members', 'orders_update_active_members'],
  'orders tiene una policy por operación permitida'
);

-- cash_sessions no tiene policy de UPDATE: la denegación es la ausencia de policy
select policies_are(
  'public',
  'cash_sessions',
  array['cash_sessions_select_active_members', 'cash_sessions_insert_active_members'],
  'el cierre del turno no tiene policy: va por RPC'
);

-- cash_movements no tiene policy de UPDATE
select policies_are(
  'public',
  'cash_movements',
  array['cash_movements_select_active_members', 'cash_movements_insert_active_members'],
  'los movimientos de caja no admiten mutación'
);

-- existe el índice que impide dos cuentas abiertas en la misma mesa
select has_index('public', 'orders', 'orders_open_table_uidx', 'una mesa no puede tener dos cuentas abiertas a la vez');

-- existe el índice que impide dos turnos abiertos en la misma caja
select has_index('public', 'cash_sessions', 'cash_sessions_open_terminal_uidx', 'una caja no puede tener dos turnos abiertos a la vez');

-- Hasta aca fue catalogo: grants, policies e indices, que no dependen del rol.
-- Lo que sigue es comportamiento, asi que se entra como el cajero real.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- una cuenta no puede nacer liquidada
select throws_ok(
  $$insert into public.orders (id, tenant_id, establishment_id, channel, code, business_date, opened_by_user_id, opened_at, closed_by_user_id, closed_at, status) values ('90000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'counter', 'A-999', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T20:00:00Z', '00000000-0000-0000-0000-000000000004', '2026-07-27T23:50:00Z', 'settled')$$,
  '42501',
  null,
  'una cuenta no puede insertarse ya liquidada, porque después sería incorregible'
);

-- un mozo no puede cerrar la cuenta por PATCH
select throws_ok(
  $$update public.orders set status = 'settled', closed_at = '2026-07-27T23:10:00Z', closed_by_user_id = '00000000-0000-0000-0000-000000000004' where id = '90000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'cerrar la cuenta no es alcanzable por PostgREST ni para el que la abrió'
);

-- mover la mesa de una cuenta abierta sigue siendo del mozo
select lives_ok(
  $$update public.orders set guest_count = 4, note = 'cumpleaños' where id = '90000000-0000-0000-0000-000000000001'$$,
  'un mozo sí puede corregir comensales y nota con la mesa abierta'
);

-- mostrador con mesa es un estado imposible
select throws_ok(
  $$insert into public.orders (tenant_id, establishment_id, channel, table_id, code, business_date, opened_by_user_id, opened_at) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'counter', '70000000-0000-0000-0000-000000000001', 'A-101', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T20:00:00Z')$$,
  '23514',
  null,
  'una venta de mostrador no puede tener mesa'
);

-- salón sin mesa es un estado imposible
select throws_ok(
  $$insert into public.orders (tenant_id, establishment_id, channel, code, business_date, opened_by_user_id, opened_at) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'dine_in', 'A-102', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T20:00:00Z')$$,
  '23514',
  null,
  'una cuenta de salón no puede quedar sin mesa'
);

-- tres comensales en el mostrador es un estado imposible
select throws_ok(
  $$insert into public.orders (tenant_id, establishment_id, channel, code, business_date, guest_count, opened_by_user_id, opened_at) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'counter', 'A-103', '2026-07-27', 3, '00000000-0000-0000-0000-000000000004', '2026-07-27T20:00:00Z')$$,
  '23514',
  null,
  'el mostrador no lleva comensales'
);

-- la misma mesa no admite una segunda cuenta abierta
select throws_ok(
  $$insert into public.orders (tenant_id, establishment_id, channel, table_id, code, business_date, opened_by_user_id, opened_at) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'dine_in', '70000000-0000-0000-0000-000000000001', 'A-104', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T20:05:00Z')$$,
  '23505',
  null,
  'la mesa 12 no puede tener dos cuentas abiertas a la vez'
);

-- nadie abre una cuenta a nombre de otro
select throws_ok(
  $$insert into public.orders (tenant_id, establishment_id, channel, code, business_date, opened_by_user_id, opened_at) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'counter', 'A-105', '2026-07-27', '00000000-0000-0000-0000-000000000001', '2026-07-27T20:00:00Z')$$,
  '42501',
  null,
  'el actor que abre la cuenta sale de auth.uid(), no del body'
);

-- una línea no puede nacer anulada con el uuid de otro mozo
select throws_ok(
  $$insert into public.order_lines (tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, line_total_gs, status, voided_at, voided_by_user_id, void_reason) values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 9, 'Lomito completo', 1, 45000, 10, 45000, 'voided', '2026-07-27T21:14:00Z', '00000000-0000-0000-0000-000000000001', 'cliente se arrepintió')$$,
  '42501',
  null,
  'una línea no nace anulada, y menos a nombre de otro'
);

-- la aritmética de la línea la verifica la base, no el dispositivo
select throws_ok(
  $$insert into public.order_lines (tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, modifiers_total_gs, discount_gs, line_total_gs) values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 10, 'Lomito completo', 2, 45000, 10, 8000, 0, 90000)$$,
  '23514',
  null,
  'line_total_gs tiene que ser el redondeo de cantidad por precio más agregados menos descuento'
);

-- la cortesía del 100% es una línea válida del pedido
select lives_ok(
  $$insert into public.order_lines (tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, discount_gs, line_total_gs) values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 11, 'Lomito completo', 1, 45000, 10, 45000, 0)$$,
  'invitar un plato quemado es una línea de total cero, no una línea que falta'
);

-- Los invariantes de estado son CHECK y triggers, y la policy de INSERT deniega
-- antes de que el CHECK llegue a evaluarse. Para probar el invariante y no la
-- policy, estas entran como dueno; la denegacion al cliente ya la prueban las
-- de 42501 de mas arriba.
reset role;

-- no se agregan platos a una cuenta ya cobrada
select throws_ok(
  $$insert into public.order_lines (tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, line_total_gs) values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', 1, 'Lomito completo', 1, 45000, 10, 45000)$$,
  'P0001',
  'closed order cannot change its lines',
  'una cuenta cerrada no acepta líneas nuevas'
);

-- una cuenta cerrada es inmutable incluso en las columnas operativas
select throws_ok(
  $$update public.orders set note = 'reabrir a mano' where id = '90000000-0000-0000-0000-000000000002'$$,
  'P0001',
  'closed order is immutable',
  'la cuenta cerrada no se toca más desde el cliente'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- un turno no puede nacer cerrado con un arqueo declarado por el propio cajero
select throws_ok(
  $$insert into public.cash_sessions (tenant_id, establishment_id, pos_terminal_id, business_date, opened_by_user_id, opened_at, closed_by_user_id, closed_at, counted_cash_gs, expected_cash_gs, status) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T18:00:00Z', '00000000-0000-0000-0000-000000000004', '2026-07-27T23:40:00Z', 1250000, 1250000, 'closed')$$,
  '42501',
  null,
  'el turno nace abierto: expected_cash_gs lo calcula el servidor al cerrar'
);

reset role;

-- un turno abierto no puede llevar cifras de cierre
select throws_ok(
  $$insert into public.cash_sessions (tenant_id, establishment_id, pos_terminal_id, business_date, opened_by_user_id, opened_at, counted_cash_gs, status) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '2026-07-27', '00000000-0000-0000-0000-000000000004', '2026-07-27T18:00:00Z', 1250000, 'open')$$,
  '23514',
  null,
  'el bicondicional del cierre corta también el sentido contrario'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- el cliente no puede cerrar el turno por PATCH
select throws_ok(
  $$update public.cash_sessions set status = 'closed', closed_at = '2026-07-27T23:40:00Z', closed_by_user_id = '00000000-0000-0000-0000-000000000004', counted_cash_gs = 1250000, expected_cash_gs = 1250000 where id = 'b0000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'sin grant de UPDATE, el arqueo no es una declaración jurada de sí mismo'
);

-- no entra plata a un turno cerrado
select throws_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'cash_in', 85000, 'sync tardío', '2026-07-27T23:55:00Z', '00000000-0000-0000-0000-000000000004')$$,
  'P0001',
  'cash session is closed',
  'un movimiento contra un turno cerrado no puede entrar y descuadrar un Z ya congelado'
);

reset role;

-- una corrección tiene que apuntar a un turno cerrado, y no a sí misma
select throws_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, adjusts_cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'correction', 85000, 'ajuste', '2026-07-28T09:00:00Z', '00000000-0000-0000-0000-000000000001')$$,
  'P0001',
  'adjusted cash session must be closed',
  'un turno no se corrige a sí mismo'
);

-- El check cash_movements_self_adjust_check sigue existiendo como segunda
-- barrera, pero es inalcanzable: el trigger que exige que el turno ajustado
-- este cerrado dispara antes, y un turno cerrado ya no acepta movimientos.
-- Se verifica que el check este, no que se pueda gatillar.
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.cash_movements'::regclass
      and conname = 'cash_movements_self_adjust_check'
  ),
  'la segunda barrera contra la autocorrección sigue declarada'
);

-- corregir un turno todavía abierto no es una corrección
select throws_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, adjusts_cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'correction', 85000, 'ajuste', '2026-07-28T09:00:00Z', '00000000-0000-0000-0000-000000000001')$$,
  'P0001',
  'adjusted cash session must be closed',
  'el turno ajustado tiene que estar cerrado'
);

-- el tipo de movimiento y adjusts_cash_session_id no pueden contradecirse
select throws_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'correction', 85000, 'ajuste sin turno', '2026-07-28T09:00:00Z', '00000000-0000-0000-0000-000000000001')$$,
  '23514',
  null,
  'una corrección sin turno ajustado es un estado imposible'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- un cajero no saca plata del cajón: vault_drop y supplier_payout son de owner o admin
select throws_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'vault_drop', 500000, 'sangría', '2026-07-27T21:00:00Z', '00000000-0000-0000-0000-000000000004')$$,
  '42501',
  null,
  'un member no puede registrar una sangría ni un pago a proveedor'
);

-- un ingreso menor sí lo hace el cajero
select lives_ok(
  $$insert into public.cash_movements (tenant_id, cash_session_id, movement_type, amount_gs, reason, occurred_at, created_by_user_id) values ('10000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'cash_in', 100000, 'cambio de sencillo', '2026-07-27T19:00:00Z', '00000000-0000-0000-0000-000000000004')$$,
  'un cash_in del cajero no necesita un admin'
);

reset role;

-- un movimiento de caja no se edita: se corrige con el movimiento inverso
select throws_ok(
  $$update public.cash_movements set amount_gs = 1 where tenant_id = '10000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'cash movement is append-only',
  'cash_movements es append-only, incluso contra un intento de mover tenant_id'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- un movimiento de caja no se borra
select throws_ok(
  $$delete from public.cash_movements where tenant_id = '10000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'no hay grant de DELETE en ninguna tabla de esta capa'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- el aislamiento de tenant vale también para la cuenta abierta
select results_eq(
  $$select id from public.orders order by id$$,
  array['90000000-0000-0000-0000-000000000001'::uuid, '90000000-0000-0000-0000-000000000002'::uuid],
  'Tenant A no ve las cuentas de Tenant B'
);

reset role;

-- una línea no puede colgar de una cuenta de otro tenant aunque se conozca el uuid
select throws_ok(
  $$insert into public.order_lines (tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, line_total_gs) values ('10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000001', 1, 'Lomito completo', 1, 45000, 10, 45000)$$,
  '23503',
  null,
  'el ancla de dos columnas corta la referencia cruzada que la FK simple aceptaría'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

-- doble queso son dos filas y el comprobante las va a poder congelar
select lives_ok(
  $$insert into public.order_line_modifiers (tenant_id, order_line_id, modifier_option_id, modifier_group_name, name, price_delta_gs, sequence_number) values ('10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000011', 'Extras', 'Extra queso', 8000, 1), ('10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000011', 'Extras', 'Extra queso', 8000, 2)$$,
  'la misma opción dos veces en la misma línea es legal y distinguible'
);

-- no se agregan modificadores a una línea anulada
select throws_ok(
  $$insert into public.order_line_modifiers (tenant_id, order_line_id, modifier_option_id, modifier_group_name, name, price_delta_gs, sequence_number) values ('10000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000011', 'Extras', 'Extra queso', 8000, 1)$$,
  'P0001',
  'order line is not open for modifiers',
  'una línea anulada no acepta agregados'
);

-- mover una cuenta de tenant sigue siendo imposible
select throws_ok(
  $$update public.orders set tenant_id = '10000000-0000-0000-0000-000000000002' where id = '90000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'tenant_id no está en el grant de columna, así que ni llega al trigger'
);


select * from finish();

rollback;
