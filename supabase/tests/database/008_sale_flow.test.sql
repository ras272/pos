begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- El flujo de venta completo, de punta a punta, por los RPC reales: abrir caja,
-- abrir mesa, cargar platos, cerrar la cuenta, emitir el comprobante, cobrar,
-- registrar la transmision a SIFEN y cerrar el turno.
--
-- Es la unica prueba que ejecuta los RPC en secuencia. Todo lo demas verifica
-- que los guardianes esten; esta verifica que la venta se pueda hacer.

insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'cajero-a@example.test');

-- RUC 80012345 con digito verificador 0, que es el que da el modulo 11.
insert into public.tenants (id, name, ruc, ruc_dv, legal_name, status)
values
  ('10000000-0000-0000-0000-000000000001', 'Lomiteria A', '80012345', 0, 'LOMITERIA A SRL', 'active');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active');

insert into public.establishments (id, tenant_id, name, establishment_code, status)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local Centro', '001', 'active');

insert into public.product_categories (id, tenant_id, name)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Lomitos');

insert into public.products (id, tenant_id, category_id, name, price_gs, iva_rate)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Lomito completo', 45000, 10),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Gaseosa', 10000, 10);

insert into public.dining_areas (id, tenant_id, establishment_id, name)
values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Salon');

insert into public.dining_tables (id, tenant_id, establishment_id, dining_area_id, code)
values
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '12');

insert into public.pos_terminals (id, tenant_id, establishment_id, name, expedition_point_code, order_code_prefix)
values
  ('80000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Caja 1', '001', 'C1');

insert into public.fiscal_timbrados (id, tenant_id, number, valid_from, valid_to, status)
values
  ('90000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '12345678', date '2026-01-01', date '2026-12-31', 'active');

insert into public.fiscal_certificates (id, tenant_id, establishment_id, issuer, serial_number, subject_ruc, not_before, expires_at, status)
values
  ('c0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'DNIT', 'F1-0001', '80012345', date '2026-01-01', date '2027-01-01', 'active');

insert into public.fiscal_thresholds (id, tenant_id, anonymous_buyer_threshold_gs, effective_from, effective_to, status)
values
  ('d0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 7000000, date '2026-01-01', null, 'active');

-- El rango de numeracion entra por RPC, como en produccion.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$select public.assign_number_range('80000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', 'invoice', 1, 1000)$$,
  'el owner asigna el rango de numeracion de la caja'
);

reset role;

-- ============================================================
-- A partir de aca opera el cajero, con su identidad verificada.
-- ============================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select lives_ok(
  $$select public.open_cash_session('b0000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', current_date, pg_catalog.now(), 100000)$$,
  'el cajero abre el turno con su fondo inicial'
);

select lives_ok(
  -- Salon: la cuenta se abre contra la MESA y no contra el turno de caja. Una
  -- mesa puede cruzar dos turnos, asi que atarla a uno seria mentir.
  $$select public.open_order('90000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-000000000001', null, 'C1-0001', current_date, pg_catalog.now(), 2::smallint, null)$$,
  'el mozo abre la mesa 12 para dos comensales'
);

select lives_ok(
  $$insert into public.order_lines (id, tenant_id, order_id, product_id, line_number, product_name, quantity, unit_price_gs, iva_rate, modifiers_total_gs, discount_gs, line_total_gs) values ('a1000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000a1', '40000000-0000-0000-0000-000000000001', 1, 'Lomito completo', 2, 45000, 10, 0, 0, 90000), ('a1000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000a1', '40000000-0000-0000-0000-000000000002', 2, 'Gaseosa', 2, 10000, 10, 0, 0, 20000)$$,
  'se cargan dos lomitos y dos gaseosas'
);

-- El orden lo impone el esquema, no una convencion: issue_document exige que
-- los cobros cubran el total, y close_order exige comprobante emitido para cada
-- linea. Se cobra, se emite, y recien entonces se cierra la cuenta.
select lives_ok(
  $$select public.register_payment('f1000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', 'cash', 110000, 0, 150000, 40000, null, pg_catalog.now(), current_date)$$,
  'se cobra en efectivo con vuelto'
);

select results_eq(
  $$select method, amount_gs::bigint, change_gs::bigint from public.payments where id = 'f1000000-0000-0000-0000-000000000001'$$,
  $$values ('cash'::text, 110000::bigint, 40000::bigint)$$,
  'el cobro queda registrado con su vuelto'
);

select lives_ok(
  $$select public.issue_document('e1000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', array['a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002']::uuid[], 1, pg_catalog.now(), current_date, null, null, null, null, null)$$,
  'se emite el comprobante innominado de Gs 110.000, por debajo del umbral'
);

-- El comprobante quedo con los valores del servidor, no del dispositivo.
select results_eq(
  $$select establishment_code, expedition_point_code, timbrado_number, number, issuer_ruc, total_gs::bigint, iva_10_gs::bigint, line_count from public.documents where id = 'e1000000-0000-0000-0000-000000000001'$$,
  $$values ('001'::text, '001'::text, '12345678'::text, 1::bigint, '80012345'::text, 110000::bigint, 10000::bigint, 2::smallint)$$,
  'el comprobante congela establecimiento, punto de expedicion, timbrado, numero, RUC y totales'
);

select is(
  (select last_number from public.document_counters where pos_terminal_id = '80000000-0000-0000-0000-000000000001' and document_type = 'invoice'),
  1::bigint,
  'el contador del rango avanzo al numero emitido'
);

-- El plazo de las 72 h se deriva en el servidor, no lo manda la tablet.
select ok(
  (
    select transmit_deadline_at - signed_at
    from public.documents
    where id = 'e1000000-0000-0000-0000-000000000001'
  ) = interval '72 hours',
  'el plazo de transmision son 72 h exactas contadas desde la firma'
);

-- Emitir dos veces el mismo documento es idempotente: es lo que permite
-- reintentar un sync sin duplicar un numero fiscal.
select results_eq(
  $$select was_created from public.issue_document('e1000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', array['a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002']::uuid[], 1, pg_catalog.now(), current_date, null, null, null, null, null)$$,
  $$values (false)$$,
  'reemitir el mismo documento no crea una fila nueva ni quema otro numero'
);

select lives_ok(
  $$select public.close_order('90000000-0000-0000-0000-0000000000a1', pg_catalog.now(), null)$$,
  'con el comprobante emitido, el mozo cierra la cuenta'
);

select lives_ok(
  $$select public.record_transmission_result('e1000000-0000-0000-0000-000000000001', null, 'approved', '0260', 'Autorizado', null, '01800123450010010000000112026072912345678901', pg_catalog.now())$$,
  'se registra la aprobacion de SIFEN'
);

select results_eq(
  $$select sifen_status, transmit_attempts from public.documents where id = 'e1000000-0000-0000-0000-000000000001'$$,
  $$values ('approved'::text, 1::smallint)$$,
  'la proyeccion del documento refleja el resultado y cuenta el intento'
);

select is(
  (select pg_catalog.count(*)::int from public.document_transmission_events where document_id = 'e1000000-0000-0000-0000-000000000001'),
  1,
  'el intento quedo en la bitacora append-only'
);

select lives_ok(
  $$select public.close_cash_session('b0000000-0000-0000-0000-000000000001', 210000, pg_catalog.now(), null)$$,
  'el cajero cierra el turno declarando lo que conto'
);

select results_eq(
  $$select status, counted_cash_gs::bigint, expected_cash_gs::bigint, cash_difference_gs::bigint from public.cash_sessions where id = 'b0000000-0000-0000-0000-000000000001'$$,
  $$values ('closed'::text, 210000::bigint, 210000::bigint, 0::bigint)$$,
  'el arqueo cuadra: fondo inicial mas el efectivo cobrado'
);

reset role;

select * from finish();

rollback;
