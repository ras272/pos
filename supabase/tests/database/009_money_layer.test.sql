begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- La capa de plata: confirmar un cobro que nacio pendiente, revertir un cobro, y
-- que el arqueo cierre bien en las dos combinaciones de turno.

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'cajero-a@example.test');

insert into public.tenants (id, name, ruc, ruc_dv, legal_name)
values
  ('10000000-0000-0000-0000-000000000001', 'Lomiteria A', '80012345', 0, 'LOMITERIA A SRL');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active');

insert into public.establishments (id, tenant_id, name, establishment_code)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local Centro', '001');

insert into public.product_categories (id, tenant_id, name)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Lomitos');

insert into public.products (id, tenant_id, category_id, name, price_gs, iva_rate)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Lomito completo', 50000, 10);

insert into public.pos_terminals (id, tenant_id, establishment_id, name, expedition_point_code, order_code_prefix)
values
  ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Caja 1', '001', 'C1');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select lives_ok(
  $$select public.open_cash_session('b0000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', current_date, pg_catalog.now(), 100000)$$,
  'se abre el turno con Gs 100.000 de fondo'
);

-- Mostrador: la cuenta se abre contra el turno de caja y no contra una mesa.
select lives_ok(
  $$select public.open_order('90000000-0000-0000-0000-0000000000b1', null, 'b0000000-0000-0000-0000-000000000001', 'C1-0001', current_date, pg_catalog.now(), null, null)$$,
  'se abre una venta de mostrador'
);

select lives_ok(
  $$insert into public.order_lines (id, tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, modifiers_total_gs, discount_gs, line_total_gs) values ('a1000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-000000000001', 1, 'Lomito completo', 1, 50000, 10, 0, 0, 50000)$$,
  'se carga un lomito'
);

-- ============================================================
-- Un cobro con QR nace pendiente y ahora se puede confirmar.
-- ============================================================
select lives_ok(
  $$select public.register_payment('f1000000-0000-0000-0000-0000000000b1', '90000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-000000000001', 'qr', 50000, 0, null, 0, null, pg_catalog.now(), current_date)$$,
  'se cobra con QR'
);

select is(
  (select status from public.payments where id = 'f1000000-0000-0000-0000-0000000000b1'),
  'pending',
  'un cobro con QR nace pendiente: la plata todavia no llego'
);

select lives_ok(
  $$select public.confirm_payment('f1000000-0000-0000-0000-0000000000b1', 'BCP-QR-99887766', pg_catalog.now())$$,
  'se confirma el QR con la referencia del banco'
);

select results_eq(
  $$select status, external_reference from public.payments where id = 'f1000000-0000-0000-0000-0000000000b1'$$,
  $$values ('confirmed'::text, 'BCP-QR-99887766'::text)$$,
  'el cobro queda confirmado con su referencia externa'
);

select throws_ok(
  $$select public.confirm_payment('f1000000-0000-0000-0000-0000000000b1', 'otra-referencia', pg_catalog.now())$$,
  'P0001',
  'only a pending payment can be confirmed',
  'confirmar dos veces el mismo cobro no cambia la referencia'
);

-- ============================================================
-- Un cobro en efectivo revertido en el MISMO turno: el arqueo tiene que
-- quedar neto cero, no restar dos veces.
-- ============================================================
select lives_ok(
  $$select public.register_payment('f1000000-0000-0000-0000-0000000000b2', '90000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-000000000001', 'cash', 50000, 0, 50000, 0, null, pg_catalog.now(), current_date)$$,
  'se cobra de mas, en efectivo, por error'
);

select throws_ok(
  $$select public.reverse_payment('e0000000-0000-0000-0000-0000000000b1', 'f1000000-0000-0000-0000-0000000000b2', 'b0000000-0000-0000-0000-000000000001', 'cobro duplicado', pg_catalog.now())$$,
  '42501',
  'owner or admin role is required to reverse a payment',
  'un cajero no revierte un cobro por su cuenta: la plata que sale del cajon es de owner o admin'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$select public.reverse_payment('e0000000-0000-0000-0000-0000000000b1', 'f1000000-0000-0000-0000-0000000000b2', 'b0000000-0000-0000-0000-000000000001', 'cobro duplicado', pg_catalog.now())$$,
  'el owner revierte el cobro duplicado'
);

select is(
  (select status from public.payments where id = 'f1000000-0000-0000-0000-0000000000b2'),
  'reversed',
  'el cobro queda revertido'
);

select results_eq(
  $$select reason, cash_session_id from public.payment_reversals where id = 'e0000000-0000-0000-0000-0000000000b1'$$,
  $$values ('cobro duplicado'::text, 'b0000000-0000-0000-0000-000000000001'::uuid)$$,
  'el reverso queda con su motivo y en el turno donde ocurrio'
);

select throws_ok(
  $$select public.reverse_payment('e0000000-0000-0000-0000-0000000000b2', 'f1000000-0000-0000-0000-0000000000b2', 'b0000000-0000-0000-0000-000000000001', 'otra vez', pg_catalog.now())$$,
  'P0001',
  'payment was already reversed',
  'un cobro no se revierte dos veces'
);

select throws_ok(
  $$select public.reverse_payment('e0000000-0000-0000-0000-0000000000b3', 'f1000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-000000000001', '', pg_catalog.now())$$,
  '22023',
  'a reversal reason is required',
  'un reverso sin motivo no entra: plata que desaparece del arqueo necesita explicacion'
);

-- ============================================================
-- El arqueo. El QR no entra al cajon; el efectivo revertido en el mismo turno
-- suma y resta, y tiene que quedar en cero.
-- ============================================================
select lives_ok(
  $$select public.close_cash_session('b0000000-0000-0000-0000-000000000001', 100000, pg_catalog.now(), null)$$,
  'se cierra el turno'
);

select results_eq(
  $$select expected_cash_gs::bigint, counted_cash_gs::bigint, cash_difference_gs::bigint from public.cash_sessions where id = 'b0000000-0000-0000-0000-000000000001'$$,
  $$values (100000::bigint, 100000::bigint, 0::bigint)$$,
  'el esperado es solo el fondo inicial: el QR no toca el cajon y el efectivo revertido neteo a cero'
);

reset role;

-- La correccion de caja ahora tiene signo, y las dos variantes son legales.
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.cash_movements'::regclass
      and conname = 'cash_movements_movement_type_check'
      and pg_catalog.pg_get_constraintdef(oid) like '%correction_in%'
      and pg_catalog.pg_get_constraintdef(oid) like '%correction_out%'
  ),
  'la correccion de caja lleva signo: correction_in y correction_out'
);

select * from finish();

rollback;
