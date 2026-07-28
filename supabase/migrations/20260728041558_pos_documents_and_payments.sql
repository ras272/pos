-- El comprobante fiscal congelado y el cobro.
--
-- Congelar no es validar: los valores fiscales se copian DESDE las tablas del
-- servidor, no desde el payload. Un check que compara el rango autorizado
-- contra si mismo, cuando los dos los manda el dispositivo, es una tautologia.
--
-- La anulacion y el reverso son filas nuevas, no columnas: en SIFEN la
-- cancelacion se transmite y se aprueba por su cuenta, con su propio ciclo.

create table public.documents (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  pos_terminal_id uuid not null,
  cash_session_id uuid not null,
  timbrado_id uuid not null,
  signing_certificate_id uuid not null,
  order_id uuid,
  customer_id uuid,
  references_document_id uuid,
  references_document_type text,
  document_type text not null,
  credit_note_scope text,
  -- Bloque congelado. Ninguna de estas columnas la escribe el dispositivo: las
  -- copia security.freeze_document_fiscal_values() desde la tabla del servidor
  -- que manda, y rechaza el insert si el cliente mando un valor distinto. Sin
  -- eso, comparar el numero contra el rango que vino en el mismo payload es una
  -- tautologia: el dispositivo aporta la cifra y tambien la vara que la mide.
  establishment_code text not null,
  expedition_point_code text not null,
  timbrado_number text not null,
  timbrado_valid_from date not null,
  timbrado_valid_to date,
  certificate_expires_at date not null,
  number bigint not null,
  authorized_range_from bigint not null,
  authorized_range_to bigint not null,
  issuer_ruc text not null,
  issuer_ruc_dv smallint not null,
  issuer_legal_name text not null,
  anonymous_buyer_threshold_gs public.guaranies not null,
  anonymous_threshold_from date not null,
  buyer_doc_type text,
  buyer_doc_number text,
  buyer_ruc_dv smallint,
  buyer_name text,
  total_gs public.guaranies not null,
  discount_total_gs public.guaranies not null default 0,
  taxable_base_10_gs public.guaranies not null default 0,
  iva_10_gs public.guaranies not null default 0,
  taxable_base_5_gs public.guaranies not null default 0,
  iva_5_gs public.guaranies not null default 0,
  -- Sella el documento: mas alla de esta cantidad no entra ninguna linea, y un
  -- reporte puede detectar un descuadre sin pasar por el RPC.
  line_count smallint not null,
  business_date date not null,
  signed_at timestamp with time zone not null,
  received_at timestamp with time zone not null default pg_catalog.now(),
  transmit_deadline_at timestamp with time zone not null,
  transmitted_at timestamp with time zone,
  sifen_status text not null default 'pending',
  sifen_response_code text,
  sifen_response_message text,
  transmit_attempts smallint not null default 0,
  cdc text,
  status text not null default 'issued',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint documents_issuer_legal_name_not_blank check (pg_catalog.btrim(issuer_legal_name) <> ''),
  constraint documents_issuer_legal_name_length_check check (pg_catalog.char_length(issuer_legal_name) <= 160),
  constraint documents_issuer_ruc_check check (issuer_ruc ~ '^[0-9]{1,8}$'),
  constraint documents_issuer_ruc_dv_check check (issuer_ruc_dv between 0 and 9),
  constraint documents_establishment_code_check check (establishment_code ~ '^[0-9]{3}$'),
  constraint documents_expedition_point_code_check check (expedition_point_code ~ '^[0-9]{3}$'),
  constraint documents_timbrado_number_check check (timbrado_number ~ '^[0-9]{8}$'),
  constraint documents_timbrado_period_check check (timbrado_valid_to is null or timbrado_valid_to >= timbrado_valid_from),
  -- Congelar la vigencia y no solo el numero es lo que vuelve el control local a
  -- la fila: un CHECK no puede mirar fiscal_timbrados, asi que sin estas dos
  -- columnas emitir con timbrado vencido no es detectable dentro de la base.
  constraint documents_timbrado_validity_check check (business_date >= timbrado_valid_from and (timbrado_valid_to is null or business_date <= timbrado_valid_to)),
  constraint documents_certificate_validity_check check (business_date <= certificate_expires_at),
  constraint documents_document_type_check check (document_type in ('invoice', 'credit_note')),
  constraint documents_invoice_order_check check (document_type <> 'invoice' or order_id is not null),
  constraint documents_reference_pair_check check ((references_document_id is null) = (references_document_type is null)),
  constraint documents_credit_note_ref_check check ((document_type = 'credit_note') = (references_document_type is not null)),
  constraint documents_credit_note_target_check check (references_document_type is null or references_document_type = 'invoice'),
  constraint documents_credit_note_scope_check check ((document_type = 'credit_note') = (credit_note_scope is not null)),
  constraint documents_credit_note_scope_value_check check (credit_note_scope is null or credit_note_scope in ('total', 'partial')),
  constraint documents_number_check check (number between 1 and 9999999),
  constraint documents_range_check check (authorized_range_to >= authorized_range_from),
  constraint documents_number_in_range_check check (number between authorized_range_from and authorized_range_to),
  constraint documents_buyer_doc_type_check check (buyer_doc_type is null or buyer_doc_type in ('RUC', 'CI')),
  constraint documents_buyer_pair_check check ((buyer_doc_type is null) = (buyer_doc_number is null)),
  -- El backstop del rechazo 1321 tiene que exigir identidad real: uno que se
  -- satisface con '0' y sin nombre no es un backstop.
  constraint documents_buyer_doc_number_check check (buyer_doc_number is null or buyer_doc_number ~ '^[0-9]+$'),
  constraint documents_buyer_doc_length_check check (buyer_doc_number is null or pg_catalog.char_length(buyer_doc_number) between 5 and 20),
  constraint documents_buyer_dv_check check (buyer_ruc_dv is null or buyer_doc_type = 'RUC'),
  constraint documents_ruc_needs_dv_check check (buyer_doc_type is distinct from 'RUC' or buyer_ruc_dv is not null),
  constraint documents_buyer_ruc_dv_range_check check (buyer_ruc_dv is null or buyer_ruc_dv between 0 and 9),
  constraint documents_buyer_name_not_blank check (buyer_name is null or pg_catalog.btrim(buyer_name) <> ''),
  constraint documents_buyer_name_length_check check (buyer_name is null or pg_catalog.char_length(buyer_name) <= 120),
  constraint documents_buyer_name_check check (buyer_doc_number is null or (buyer_name is not null and pg_catalog.char_length(pg_catalog.btrim(buyer_name)) >= 3)),
  constraint documents_anonymous_check check (total_gs <= anonymous_buyer_threshold_gs or buyer_doc_number is not null),
  constraint documents_total_positive_check check (total_gs > 0),
  constraint documents_totals_check check (taxable_base_10_gs + iva_10_gs + taxable_base_5_gs + iva_5_gs = total_gs),
  constraint documents_line_count_check check (line_count > 0),
  -- El plazo legal queda clavado a la firma con una expresion IMMUTABLE: la
  -- resta de timestamptz y date_part('epoch', interval) si lo son, mientras que
  -- `signed_at + interval '72 hours'` es STABLE y Postgres rechaza el DDL. El
  -- trigger escribe el valor, este check garantiza que sean 72 h exactas.
  constraint documents_transmit_deadline_check check (pg_catalog.date_part('epoch', transmit_deadline_at - signed_at) = 259200),
  constraint documents_sifen_status_check check (sifen_status in ('pending', 'transmitted', 'approved', 'rejected')),
  constraint documents_transmitted_at_check check ((sifen_status = 'pending') = (transmitted_at is null)),
  constraint documents_transmit_attempts_check check (transmit_attempts >= 0),
  constraint documents_sifen_response_code_length_check check (sifen_response_code is null or pg_catalog.char_length(sifen_response_code) <= 10),
  constraint documents_sifen_response_message_length_check check (sifen_response_message is null or pg_catalog.char_length(sifen_response_message) <= 1000),
  constraint documents_cdc_check check (cdc is null or cdc ~ '^[0-9]{44}$'),
  constraint documents_status_check check (status in ('issued', 'cancelled')),
  constraint documents_id_tenant_id_key unique (id, tenant_id),
  -- Ancla de tres columnas: deja que document_lines lleve el tipo congelado sin
  -- poder mentir, que es lo que vuelve real la unicidad por linea de pedido.
  constraint documents_id_tenant_id_document_type_key unique (id, tenant_id, document_type),
  constraint documents_pos_terminal_id_document_type_timbrado_id_number_key unique (pos_terminal_id, document_type, timbrado_id, number),
  -- Nombre acortado a proposito: el canonico enumerando las seis columnas pasa
  -- los 63 caracteres y Postgres lo truncaria en silencio. Cubre lo que la
  -- unique de arriba no ve, que son los codigos CONGELADOS: reordenar los puntos
  -- de expedicion no puede producir dos comprobantes con el mismo numero impreso.
  constraint documents_fiscal_number_key unique (tenant_id, establishment_code, expedition_point_code, timbrado_number, document_type, number),
  constraint documents_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  constraint documents_pos_terminal_id_fkey foreign key (pos_terminal_id, establishment_id)
    references public.pos_terminals (id, establishment_id) on delete restrict,
  -- Anclado por TERMINAL y no por tenant: una caja es un punto de expedicion, y
  -- el turno tiene que ser del mismo terminal que emitio o el arqueo de dos
  -- cajas del mismo local queda mintiendo el mismo dia.
  constraint documents_cash_session_id_fkey foreign key (cash_session_id, pos_terminal_id)
    references public.cash_sessions (id, pos_terminal_id) on delete restrict,
  constraint documents_order_id_fkey foreign key (order_id, establishment_id)
    references public.orders (id, establishment_id) on delete restrict,
  constraint documents_customer_id_fkey foreign key (customer_id, tenant_id)
    references public.customers (id, tenant_id) on delete restrict,
  constraint documents_timbrado_id_fkey foreign key (timbrado_id, tenant_id)
    references public.fiscal_timbrados (id, tenant_id) on delete restrict,
  constraint documents_certificate_id_fkey foreign key (signing_certificate_id, tenant_id)
    references public.fiscal_certificates (id, tenant_id) on delete restrict,
  constraint documents_references_document_id_fkey foreign key (references_document_id, tenant_id, references_document_type)
    references public.documents (id, tenant_id, document_type) on delete restrict
);

create table public.document_lines (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  document_id uuid not null,
  -- Denormalizado y anclado a documents (id, tenant_id, document_type): no puede
  -- mentir. Es lo que vuelve obligatorio order_line_id en las facturas, y con
  -- eso el unique parcial de trazabilidad deja de ser opcional justo donde tiene
  -- que ser obligatorio.
  document_type text not null,
  order_line_id uuid,
  product_id uuid not null,
  line_number smallint not null,
  product_name text not null,
  product_category_name text not null,
  quantity numeric(12, 3) not null,
  unit_price_gs public.guaranies not null,
  modifiers_total_gs bigint not null default 0,
  discount_gs public.guaranies not null default 0,
  iva_rate smallint not null,
  taxable_base_gs public.guaranies not null,
  iva_amount_gs public.guaranies not null,
  line_total_gs public.guaranies not null,
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint document_lines_product_name_not_blank check (pg_catalog.btrim(product_name) <> ''),
  constraint document_lines_product_name_length_check check (pg_catalog.char_length(product_name) <= 120),
  constraint document_lines_product_category_name_not_blank check (pg_catalog.btrim(product_category_name) <> ''),
  constraint document_lines_product_category_name_length_check check (pg_catalog.char_length(product_category_name) <= 80),
  constraint document_lines_line_number_check check (line_number between 1 and 999),
  constraint document_lines_quantity_check check (quantity > 0),
  constraint document_lines_iva_rate_check check (iva_rate in (5, 10)),
  constraint document_lines_composition_check check (line_total_gs = pg_catalog.round(quantity * (unit_price_gs + modifiers_total_gs))::bigint - discount_gs),
  constraint document_lines_iva_split_check check (taxable_base_gs + iva_amount_gs = line_total_gs),
  -- La desagregacion como CHECK y no como columna generada: una generada
  -- corregiria en silencio a un dispositivo que redondee distinto y el papel ya
  -- se imprimio. El residuo cae siempre en la base, que se deriva restando.
  constraint document_lines_iva_amount_check check (iva_amount_gs = pg_catalog.round((line_total_gs::numeric * iva_rate) / (100 + iva_rate))::bigint),
  -- La cortesia (100% bonificado) es rutina despues de un reclamo: se admite el
  -- cero solo cuando esta justificado por un descuento explicito y visible.
  constraint document_lines_zero_total_check check (line_total_gs > 0 or discount_gs > 0),
  constraint document_lines_document_type_check check (document_type in ('invoice', 'credit_note')),
  constraint document_lines_invoice_trace_check check ((document_type = 'invoice') = (order_line_id is not null)),
  constraint document_lines_id_tenant_id_key unique (id, tenant_id),
  constraint document_lines_document_id_line_number_key unique (document_id, line_number),
  constraint document_lines_document_id_fkey foreign key (document_id, tenant_id, document_type)
    references public.documents (id, tenant_id, document_type) on delete restrict,
  constraint document_lines_order_line_id_fkey foreign key (order_line_id, tenant_id)
    references public.order_lines (id, tenant_id) on delete restrict,
  constraint document_lines_product_id_fkey foreign key (product_id, tenant_id)
    references public.products (id, tenant_id) on delete restrict
);

create table public.document_line_modifiers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  document_line_id uuid not null,
  modifier_option_id uuid not null,
  modifier_group_name text not null,
  name text not null,
  price_delta_gs bigint not null,
  -- Identidad, no presentacion. Con unique (document_line_id, display_order) la
  -- forma canonica de 'doble queso' (dos filas de la misma opcion, ambas con
  -- display_order 0) es representable en el pedido e imposible de congelar.
  sequence_number smallint not null,
  display_order smallint not null default 0,
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint document_line_modifiers_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint document_line_modifiers_name_length_check check (pg_catalog.char_length(name) <= 80),
  constraint document_line_modifiers_modifier_group_name_not_blank check (pg_catalog.btrim(modifier_group_name) <> ''),
  constraint document_line_modifiers_modifier_group_name_length_check check (pg_catalog.char_length(modifier_group_name) <= 80),
  constraint document_line_modifiers_sequence_number_check check (sequence_number > 0),
  constraint document_line_modifiers_display_order_check check (display_order >= 0),
  constraint document_line_modifiers_document_line_id_sequence_number_key unique (document_line_id, sequence_number),
  constraint document_line_modifiers_document_line_id_fkey foreign key (document_line_id, tenant_id)
    references public.document_lines (id, tenant_id) on delete restrict,
  constraint document_line_modifiers_modifier_option_id_fkey foreign key (modifier_option_id, tenant_id)
    references public.modifier_options (id, tenant_id) on delete restrict
);

create table public.document_cancellations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  document_id uuid not null,
  reason text not null,
  requested_at timestamp with time zone not null,
  received_at timestamp with time zone not null default pg_catalog.now(),
  requested_by_user_id uuid not null references auth.users (id) on delete restrict,
  transmitted_at timestamp with time zone,
  transmit_attempts smallint not null default 0,
  response_code text,
  response_message text,
  -- sifen_status ES la columna de estado de esta tabla: no hay un segundo
  -- `status` que pueda contradecirla.
  sifen_status text not null default 'pending',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint document_cancellations_reason_length_check check (pg_catalog.char_length(pg_catalog.btrim(reason)) between 10 and 500),
  constraint document_cancellations_sifen_status_check check (sifen_status in ('pending', 'transmitted', 'approved', 'rejected')),
  constraint document_cancellations_transmitted_check check ((sifen_status = 'pending') = (transmitted_at is null)),
  constraint document_cancellations_transmit_attempts_check check (transmit_attempts >= 0),
  constraint document_cancellations_response_code_length_check check (response_code is null or pg_catalog.char_length(response_code) <= 10),
  constraint document_cancellations_response_message_length_check check (response_message is null or pg_catalog.char_length(response_message) <= 1000),
  constraint document_cancellations_id_tenant_id_key unique (id, tenant_id),
  constraint document_cancellations_document_id_fkey foreign key (document_id, tenant_id)
    references public.documents (id, tenant_id) on delete restrict
);

create table public.document_transmission_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  document_id uuid,
  document_cancellation_id uuid,
  attempt_number smallint not null,
  outcome text not null,
  -- Sin el prefijo `sifen_`: la tabla ya se llama ..._transmission_events, y con
  -- el, el nombre canonico del check de largo mide 64 caracteres. Postgres lo
  -- truncaria a 63 con un simple NOTICE y todo assert por nombre fallaria.
  response_code text,
  response_message text,
  -- SHA-256 del XML enviado. Nunca el XML, nunca el certificado, nunca material
  -- de clave.
  request_payload_hash text,
  transmitted_at timestamp with time zone not null,
  status text not null default 'recorded',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint document_transmission_events_subject_check check (pg_catalog.num_nonnulls(document_id, document_cancellation_id) = 1),
  constraint document_transmission_events_attempt_number_check check (attempt_number > 0),
  constraint document_transmission_events_outcome_check check (outcome in ('approved', 'rejected', 'network_error', 'timeout', 'retry')),
  constraint document_transmission_events_response_check check (outcome not in ('approved', 'rejected') or response_code is not null),
  constraint document_transmission_events_response_code_length_check check (response_code is null or pg_catalog.char_length(response_code) <= 10),
  constraint document_transmission_events_response_message_length_check check (response_message is null or pg_catalog.char_length(response_message) <= 1000),
  constraint document_transmission_events_hash_check check (request_payload_hash is null or request_payload_hash ~ '^[0-9a-f]{64}$'),
  constraint document_transmission_events_status_check check (status in ('recorded')),
  constraint document_transmission_events_document_id_fkey foreign key (document_id, tenant_id)
    references public.documents (id, tenant_id) on delete restrict,
  constraint document_transmission_events_cancellation_id_fkey foreign key (document_cancellation_id, tenant_id)
    references public.document_cancellations (id, tenant_id) on delete restrict
);

create table public.payments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  order_id uuid not null,
  pos_terminal_id uuid not null,
  cash_session_id uuid not null,
  document_id uuid,
  method text not null,
  amount_gs public.guaranies not null,
  -- LA PROPINA, fuera de la base imponible y fuera de documents.total_gs.
  -- Meterla como linea de venta la volveria gravada; PY-QR ya la trae nativa
  -- (campos 55/56/57) y ocurre en el cobro, no en la venta.
  tip_gs public.guaranies not null default 0,
  charged_total_gs bigint generated always as (amount_gs + tip_gs) stored,
  tendered_gs public.guaranies,
  change_gs public.guaranies not null default 0,
  external_reference text,
  external_confirmed_at timestamp with time zone,
  occurred_at timestamp with time zone not null,
  business_date date not null,
  created_by_user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'confirmed',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint payments_method_check check (method in ('cash', 'card_debit', 'card_credit', 'qr', 'transfer', 'other')),
  constraint payments_amount_gs_check check (amount_gs > 0),
  constraint payments_tendered_check check (tendered_gs is null or tendered_gs = amount_gs + tip_gs + change_gs),
  constraint payments_change_cash_check check (method = 'cash' or change_gs = 0),
  constraint payments_cash_no_reference_check check (method <> 'cash' or external_reference is null),
  constraint payments_external_reference_length_check check (external_reference is null or pg_catalog.char_length(external_reference) <= 120),
  constraint payments_confirmation_check check (external_confirmed_at is null or external_reference is not null),
  constraint payments_status_check check (status in ('pending', 'confirmed', 'reversed')),
  constraint payments_id_tenant_id_key unique (id, tenant_id),
  constraint payments_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  constraint payments_order_id_fkey foreign key (order_id, establishment_id)
    references public.orders (id, establishment_id) on delete restrict,
  constraint payments_pos_terminal_id_fkey foreign key (pos_terminal_id, establishment_id)
    references public.pos_terminals (id, establishment_id) on delete restrict,
  constraint payments_cash_session_id_fkey foreign key (cash_session_id, pos_terminal_id)
    references public.cash_sessions (id, pos_terminal_id) on delete restrict,
  constraint payments_document_id_fkey foreign key (document_id, tenant_id)
    references public.documents (id, tenant_id) on delete restrict
);

create table public.payment_reversals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  payment_id uuid not null,
  -- El turno VIGENTE donde se hizo el reverso, no el del cobro original. Es la
  -- unica razon por la que esta tabla existe en vez de un payments.status.
  cash_session_id uuid not null,
  reason text not null,
  reversed_at timestamp with time zone not null,
  reversed_by_user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'recorded',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint payment_reversals_reason_not_blank check (pg_catalog.btrim(reason) <> ''),
  constraint payment_reversals_reason_length_check check (pg_catalog.char_length(reason) <= 300),
  constraint payment_reversals_status_check check (status in ('recorded')),
  constraint payment_reversals_payment_id_tenant_id_key unique (payment_id, tenant_id),
  constraint payment_reversals_payment_id_fkey foreign key (payment_id, tenant_id)
    references public.payments (id, tenant_id) on delete restrict,
  constraint payment_reversals_cash_session_id_fkey foreign key (cash_session_id, tenant_id)
    references public.cash_sessions (id, tenant_id) on delete restrict
);

create function security.ruc_check_digit(p_ruc text)
returns smallint
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_total integer := 0;
  v_base integer := 2;
  v_position integer;
  v_remainder integer;
begin
  if p_ruc is null or p_ruc !~ '^[0-9]+$' then
    return null;
  end if;

  for v_position in reverse pg_catalog.char_length(p_ruc)..1 loop
    v_total := v_total + pg_catalog.substr(p_ruc, v_position, 1)::integer * v_base;
    v_base := v_base + 1;

    if v_base > 11 then
      v_base := 2;
    end if;
  end loop;

  v_remainder := v_total % 11;

  if v_remainder > 1 then
    return (11 - v_remainder)::smallint;
  end if;

  return 0::smallint;
end;
$$;

create function security.freeze_document_fiscal_values()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_establishment_code text;
  v_expedition_point_code text;
  v_timbrado_number text;
  v_timbrado_valid_from date;
  v_timbrado_valid_to date;
  v_range_from bigint;
  v_range_to bigint;
  v_threshold_gs bigint;
  v_threshold_from date;
  v_issuer_ruc text;
  v_issuer_ruc_dv smallint;
  v_issuer_legal_name text;
  v_certificate_expires_at date;
begin
  -- El reloj de la tablet no puede correr un plazo legal. El futuro nunca es
  -- legitimo; el pasado si, y es exactamente el caso que hay que reportar.
  new.received_at := pg_catalog.now();

  if new.signed_at > new.received_at + interval '5 minutes' then
    raise exception using
      errcode = 'P0001',
      message = 'signed_at cannot be in the future';
  end if;

  if new.signed_at < new.received_at - interval '30 days' then
    raise exception using
      errcode = 'P0001',
      message = 'signed_at is older than the reportable window';
  end if;

  new.transmit_deadline_at := new.signed_at + interval '72 hours';

  select tenant.ruc, tenant.ruc_dv, tenant.legal_name
    into v_issuer_ruc, v_issuer_ruc_dv, v_issuer_legal_name
  from public.tenants as tenant
  where tenant.id = new.tenant_id;

  if v_issuer_ruc is null or v_issuer_ruc_dv is null or v_issuer_legal_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'issuer fiscal identity is not configured';
  end if;

  select establishment.establishment_code
    into v_establishment_code
  from public.establishments as establishment
  where establishment.id = new.establishment_id
    and establishment.tenant_id = new.tenant_id;

  select pos_terminal.expedition_point_code
    into v_expedition_point_code
  from public.pos_terminals as pos_terminal
  where pos_terminal.id = new.pos_terminal_id
    and pos_terminal.establishment_id = new.establishment_id;

  if v_establishment_code is null or v_expedition_point_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal codes are not configured';
  end if;

  select timbrado.number, timbrado.valid_from, timbrado.valid_to
    into v_timbrado_number, v_timbrado_valid_from, v_timbrado_valid_to
  from public.fiscal_timbrados as timbrado
  where timbrado.id = new.timbrado_id
    and timbrado.tenant_id = new.tenant_id
    and timbrado.status = 'active';

  if v_timbrado_number is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal stamp is not active';
  end if;

  -- La fila del contador que CONTIENE el numero, no la vigente: renovar el rango
  -- no puede dejar irrecuperable un comprobante ya impreso del rango anterior.
  select counter.range_from, counter.range_to
    into v_range_from, v_range_to
  from public.document_counters as counter
  where counter.pos_terminal_id = new.pos_terminal_id
    and counter.document_type = new.document_type
    and counter.timbrado_id = new.timbrado_id
    and new.number between counter.range_from and counter.range_to;

  if v_range_from is null then
    raise exception using
      errcode = 'P0001',
      message = 'document number outside every authorized range';
  end if;

  -- Por la fecha de la VENTA, nunca por now(): con 72 h de ventana, sincronizar
  -- despues de un decreto es el caso ordinario. Una venta legal bajo el umbral
  -- viejo tiene que poder guardarse, y una posterior al decreto no.
  select threshold.anonymous_buyer_threshold_gs, threshold.effective_from
    into v_threshold_gs, v_threshold_from
  from public.fiscal_thresholds as threshold
  where threshold.tenant_id = new.tenant_id
    and threshold.effective_from <= new.business_date
    and (threshold.effective_to is null or new.business_date < threshold.effective_to)
  order by threshold.effective_from desc
  limit 1;

  if v_threshold_gs is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal threshold is not configured';
  end if;

  select certificate.expires_at
    into v_certificate_expires_at
  from public.fiscal_certificates as certificate
  where certificate.id = new.signing_certificate_id
    and certificate.tenant_id = new.tenant_id
    and certificate.status = 'active';

  if v_certificate_expires_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'signing certificate is not active';
  end if;

  -- Una divergencia significa que el papel impreso y el servidor no dicen lo
  -- mismo. Se rechaza, no se corrige en silencio: hay que enterarse antes de
  -- transmitir, no despues del rechazo de SIFEN.
  if (new.establishment_code is not null and new.establishment_code is distinct from v_establishment_code)
    or (new.expedition_point_code is not null and new.expedition_point_code is distinct from v_expedition_point_code)
    or (new.timbrado_number is not null and new.timbrado_number is distinct from v_timbrado_number)
    or (new.authorized_range_from is not null and new.authorized_range_from is distinct from v_range_from)
    or (new.authorized_range_to is not null and new.authorized_range_to is distinct from v_range_to)
    or (new.anonymous_buyer_threshold_gs is not null and new.anonymous_buyer_threshold_gs is distinct from v_threshold_gs)
  then
    raise exception using
      errcode = 'P0001',
      message = 'frozen fiscal values do not match the server';
  end if;

  new.establishment_code := v_establishment_code;
  new.expedition_point_code := v_expedition_point_code;
  new.timbrado_number := v_timbrado_number;
  new.timbrado_valid_from := v_timbrado_valid_from;
  new.timbrado_valid_to := v_timbrado_valid_to;
  new.authorized_range_from := v_range_from;
  new.authorized_range_to := v_range_to;
  new.anonymous_buyer_threshold_gs := v_threshold_gs;
  new.anonymous_threshold_from := v_threshold_from;
  new.issuer_ruc := v_issuer_ruc;
  new.issuer_ruc_dv := v_issuer_ruc_dv;
  new.issuer_legal_name := v_issuer_legal_name;
  new.certificate_expires_at := v_certificate_expires_at;

  if new.buyer_doc_type = 'RUC'
     and new.buyer_ruc_dv is distinct from security.ruc_check_digit(new.buyer_doc_number) then
    raise exception using
      errcode = 'P0001',
      message = 'buyer ruc check digit is invalid';
  end if;

  return new;
end;
$$;

create function security.prevent_document_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mutable constant text[] := array[
    'sifen_status',
    'sifen_response_code',
    'sifen_response_message',
    'transmit_attempts',
    'transmitted_at',
    'cdc',
    'status',
    'updated_at'
  ];
begin
  if tg_op = 'DELETE' then
    raise exception 'document is append-only';
  end if;

  if old.sifen_status = 'approved' and new.sifen_status is distinct from 'approved' then
    raise exception 'approved document cannot regress';
  end if;

  if old.sifen_status in ('transmitted', 'rejected') and new.sifen_status = 'pending' then
    raise exception 'sifen status cannot return to pending';
  end if;

  if old.status = 'cancelled' and new.status is distinct from 'cancelled' then
    raise exception 'document cancellation is final';
  end if;

  -- La proyeccion no se mueve sin la fila-verdad que la justifica.
  if new.status = 'cancelled' and not exists (
    select 1
    from public.document_cancellations as cancellation
    where cancellation.document_id = new.id
      and cancellation.sifen_status = 'approved'
  ) then
    raise exception 'document cancellation requires an approved cancellation';
  end if;

  if new.transmit_attempts < old.transmit_attempts then
    raise exception 'transmit attempts cannot decrease';
  end if;

  if old.cdc is not null and new.cdc is distinct from old.cdc then
    raise exception 'cdc is immutable';
  end if;

  -- Se compara por jsonb menos la lista de columnas moviles y no columna por
  -- columna: una columna que alguien agregue manana nace inmutable y el trigger
  -- falla cerrado. Es la unica capa que tampoco saltea service_role.
  if pg_catalog.to_jsonb(new) - v_mutable is distinct from pg_catalog.to_jsonb(old) - v_mutable then
    raise exception 'document is frozen';
  end if;

  return new;
end;
$$;

create function security.guard_document_line()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_line_count smallint;
  v_product_iva_rate smallint;
begin
  select document.line_count
    into v_line_count
  from public.documents as document
  where document.id = new.document_id;

  if v_line_count is null then
    raise exception using
      errcode = 'P0001',
      message = 'document does not exist';
  end if;

  -- Sin esto, a un documento ya transmitido y aprobado se le pueden AGREGAR
  -- lineas en otra transaccion y la suma deja de coincidir con los totales
  -- congelados sin que nada avise.
  if (
    select pg_catalog.count(*)
    from public.document_lines as line
    where line.document_id = new.document_id
  ) >= v_line_count then
    raise exception using
      errcode = 'P0001',
      message = 'document is sealed';
  end if;

  if new.order_line_id is not null and exists (
    select 1
    from public.order_lines as order_line
    where order_line.id = new.order_line_id
      and order_line.status = 'voided'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'voided order line cannot be invoiced';
  end if;

  select product.iva_rate
    into v_product_iva_rate
  from public.products as product
  where product.id = new.product_id
    and product.tenant_id = new.tenant_id;

  -- La tasa es la unica cifra que la DNIT audita y hoy la escribe entera el
  -- dispositivo: los tres checks de la fila pasan igual con 5% en un producto
  -- de 10%, porque la fila es internamente consistente.
  if v_product_iva_rate is distinct from new.iva_rate then
    raise exception using
      errcode = 'P0001',
      message = 'line iva rate does not match product iva rate';
  end if;

  return new;
end;
$$;

create function security.guard_document_cancellation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signed_at timestamp with time zone;
  v_status text;
begin
  select document.signed_at, document.status
    into v_signed_at, v_status
  from public.documents as document
  where document.id = new.document_id
    and document.tenant_id = new.tenant_id;

  if v_signed_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'document does not exist';
  end if;

  if v_status = 'cancelled' then
    raise exception using
      errcode = 'P0001',
      message = 'document is already cancelled';
  end if;

  if new.requested_at < v_signed_at then
    raise exception using
      errcode = 'P0001',
      message = 'cancellation cannot precede the document';
  end if;

  new.received_at := pg_catalog.now();

  return new;
end;
$$;

create function security.prevent_cancellation_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mutable constant text[] := array[
    'sifen_status',
    'response_code',
    'response_message',
    'transmit_attempts',
    'transmitted_at',
    'updated_at'
  ];
begin
  if tg_op = 'DELETE' then
    raise exception 'document cancellation is append-only';
  end if;

  if old.sifen_status = 'approved' and new.sifen_status is distinct from 'approved' then
    raise exception 'approved cancellation cannot regress';
  end if;

  if old.sifen_status in ('transmitted', 'rejected') and new.sifen_status = 'pending' then
    raise exception 'sifen status cannot return to pending';
  end if;

  if new.transmit_attempts < old.transmit_attempts then
    raise exception 'transmit attempts cannot decrease';
  end if;

  if pg_catalog.to_jsonb(new) - v_mutable is distinct from pg_catalog.to_jsonb(old) - v_mutable then
    raise exception 'document cancellation is frozen';
  end if;

  return new;
end;
$$;

create function security.prevent_payment_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_mutable constant text[] := array[
    'document_id',
    'status',
    'external_reference',
    'external_confirmed_at',
    'updated_at'
  ];
begin
  if tg_op = 'DELETE' then
    raise exception 'payment is append-only';
  end if;

  if old.document_id is not null and new.document_id is distinct from old.document_id then
    raise exception 'payment document is immutable';
  end if;

  if old.external_reference is not null and new.external_reference is distinct from old.external_reference then
    raise exception 'payment external reference is immutable';
  end if;

  if old.status = 'reversed' and new.status is distinct from 'reversed' then
    raise exception 'reversed payment is final';
  end if;

  if old.status = 'confirmed' and new.status = 'pending' then
    raise exception 'confirmed payment cannot return to pending';
  end if;

  -- Plata que desaparece del arqueo tiene que tener autor, motivo y turno.
  if new.status = 'reversed' and not exists (
    select 1
    from public.payment_reversals as reversal
    where reversal.payment_id = new.id
  ) then
    raise exception 'reversed payment requires a reversal row';
  end if;

  if pg_catalog.to_jsonb(new) - v_mutable is distinct from pg_catalog.to_jsonb(old) - v_mutable then
    raise exception 'payment is frozen';
  end if;

  return new;
end;
$$;

-- security.require_open_cash_session ya la crea la migracion de la cuenta y la caja; no se redeclara.

create function security.guard_payment_document()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.document_id is not null and not exists (
    select 1
    from public.documents as document
    where document.id = new.document_id
      and document.tenant_id = new.tenant_id
      and document.order_id = new.order_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'payment document belongs to another order';
  end if;

  return new;
end;
$$;

create function security.guard_payment_reversal()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_occurred_at timestamp with time zone;
  v_status text;
begin
  select payment.occurred_at, payment.status
    into v_occurred_at, v_status
  from public.payments as payment
  where payment.id = new.payment_id
    and payment.tenant_id = new.tenant_id;

  if v_occurred_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'payment does not exist';
  end if;

  if v_status = 'reversed' then
    raise exception using
      errcode = 'P0001',
      message = 'payment is already reversed';
  end if;

  if new.reversed_at < v_occurred_at then
    raise exception using
      errcode = 'P0001',
      message = 'reversal cannot precede the payment';
  end if;

  return new;
end;
$$;

create function security.prevent_append_only_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;

create function security.existing_document_summary(
  p_document_id uuid,
  p_tenant_id uuid
)
returns table (
  document_id uuid,
  number bigint,
  total_gs public.guaranies,
  sifen_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select document.id, document.number, document.total_gs, document.sifen_status
  from public.documents as document
  where document.id = p_document_id
    and document.tenant_id = p_tenant_id;

  if not found and exists (
    select 1
    from public.documents as document
    where document.id = p_document_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'document id collision';
  end if;

  return;
end;
$$;

create index documents_tenant_id_updated_at_idx on public.documents (tenant_id, updated_at);
create index documents_establishment_id_tenant_id_idx on public.documents (establishment_id, tenant_id);
create index documents_pos_terminal_id_establishment_id_idx on public.documents (pos_terminal_id, establishment_id);
create index documents_cash_session_id_pos_terminal_id_idx on public.documents (cash_session_id, pos_terminal_id);
create index documents_order_id_establishment_id_idx on public.documents (order_id, establishment_id);
create index documents_customer_id_tenant_id_idx on public.documents (customer_id, tenant_id);
create index documents_timbrado_id_tenant_id_idx on public.documents (timbrado_id, tenant_id);
create index documents_signing_certificate_id_tenant_id_idx on public.documents (signing_certificate_id, tenant_id);
create index documents_references_doc_tenant_type_idx on public.documents (references_document_id, tenant_id, references_document_type);
create index documents_transmit_queue_idx on public.documents (transmit_deadline_at) where sifen_status = 'pending';
create index documents_pending_by_tenant_idx on public.documents (tenant_id, transmit_deadline_at) where sifen_status = 'pending';
create index documents_rejected_idx on public.documents (tenant_id, transmit_deadline_at) where sifen_status = 'rejected';
create index documents_establishment_business_date_idx on public.documents (establishment_id, business_date);
create unique index documents_tenant_id_cdc_uidx on public.documents (tenant_id, cdc) where cdc is not null;
create unique index documents_credit_note_total_uidx on public.documents (references_document_id) where document_type = 'credit_note' and credit_note_scope = 'total' and status <> 'cancelled';
create index document_lines_tenant_id_created_at_idx on public.document_lines (tenant_id, created_at);
create index document_lines_document_id_tenant_id_type_idx on public.document_lines (document_id, tenant_id, document_type);
create index document_lines_order_line_id_tenant_id_idx on public.document_lines (order_line_id, tenant_id);
create index document_lines_product_id_tenant_id_idx on public.document_lines (product_id, tenant_id);
create unique index document_lines_order_line_uidx on public.document_lines (tenant_id, order_line_id) where order_line_id is not null;
create index document_line_modifiers_tenant_id_created_at_idx on public.document_line_modifiers (tenant_id, created_at);
create index document_line_modifiers_document_line_id_tenant_id_idx on public.document_line_modifiers (document_line_id, tenant_id);
create index document_line_modifiers_modifier_option_id_tenant_id_idx on public.document_line_modifiers (modifier_option_id, tenant_id);
create index document_cancellations_tenant_id_updated_at_idx on public.document_cancellations (tenant_id, updated_at);
create index document_cancellations_document_id_tenant_id_idx on public.document_cancellations (document_id, tenant_id);
create index document_cancellations_requested_by_user_id_idx on public.document_cancellations (requested_by_user_id);
create unique index document_cancellations_open_uidx on public.document_cancellations (document_id) where sifen_status in ('pending', 'transmitted', 'approved');
create index document_cancellations_queue_idx on public.document_cancellations (requested_at) where sifen_status = 'pending';
create index document_transmission_events_tenant_id_created_at_idx on public.document_transmission_events (tenant_id, created_at);
create index document_transmission_events_document_id_tenant_id_idx on public.document_transmission_events (document_id, tenant_id);
create index document_transmission_events_cancel_id_tenant_id_idx on public.document_transmission_events (document_cancellation_id, tenant_id);
create unique index document_transmission_events_document_attempt_uidx on public.document_transmission_events (document_id, attempt_number) where document_id is not null;
create unique index document_transmission_events_cancel_attempt_uidx on public.document_transmission_events (document_cancellation_id, attempt_number) where document_cancellation_id is not null;
create index payments_tenant_id_updated_at_idx on public.payments (tenant_id, updated_at);
create index payments_establishment_id_tenant_id_idx on public.payments (establishment_id, tenant_id);
create index payments_order_id_establishment_id_idx on public.payments (order_id, establishment_id);
create index payments_pos_terminal_id_establishment_id_idx on public.payments (pos_terminal_id, establishment_id);
create index payments_cash_session_id_pos_terminal_id_idx on public.payments (cash_session_id, pos_terminal_id);
create index payments_document_id_tenant_id_idx on public.payments (document_id, tenant_id);
create index payments_created_by_user_id_idx on public.payments (created_by_user_id);
create index payments_cash_session_id_method_idx on public.payments (cash_session_id, method);
create index payments_pending_idx on public.payments (tenant_id, occurred_at) where status = 'pending';
create unique index payments_external_reference_uidx on public.payments (tenant_id, method, external_reference) where external_reference is not null;
create index payment_reversals_tenant_id_created_at_idx on public.payment_reversals (tenant_id, created_at);
create index payment_reversals_cash_session_id_tenant_id_idx on public.payment_reversals (cash_session_id, tenant_id);
create index payment_reversals_reversed_by_user_id_idx on public.payment_reversals (reversed_by_user_id);

create trigger documents_freeze_fiscal_values
before insert on public.documents
for each row
execute function security.freeze_document_fiscal_values();

create trigger documents_frozen
before update or delete on public.documents
for each row
execute function security.prevent_document_mutation();

create trigger documents_tenant_id_immutable
before update on public.documents
for each row
execute function security.prevent_tenant_id_change();

create trigger documents_updated_at
before update on public.documents
for each row
execute function security.set_updated_at();

create trigger document_lines_append_only
before update or delete on public.document_lines
for each row
execute function security.prevent_append_only_mutation();

create trigger document_lines_guard
before insert on public.document_lines
for each row
execute function security.guard_document_line();

create trigger document_lines_tenant_id_immutable
before update on public.document_lines
for each row
execute function security.prevent_tenant_id_change();

create trigger document_lines_updated_at
before update on public.document_lines
for each row
execute function security.set_updated_at();

create trigger document_line_modifiers_append_only
before update or delete on public.document_line_modifiers
for each row
execute function security.prevent_append_only_mutation();

create trigger document_line_modifiers_tenant_id_immutable
before update on public.document_line_modifiers
for each row
execute function security.prevent_tenant_id_change();

create trigger document_line_modifiers_updated_at
before update on public.document_line_modifiers
for each row
execute function security.set_updated_at();

create trigger document_cancellations_frozen
before update or delete on public.document_cancellations
for each row
execute function security.prevent_cancellation_mutation();

create trigger document_cancellations_guard
before insert on public.document_cancellations
for each row
execute function security.guard_document_cancellation();

create trigger document_cancellations_tenant_id_immutable
before update on public.document_cancellations
for each row
execute function security.prevent_tenant_id_change();

create trigger document_cancellations_updated_at
before update on public.document_cancellations
for each row
execute function security.set_updated_at();

create trigger document_transmission_events_append_only
before update or delete on public.document_transmission_events
for each row
execute function security.prevent_append_only_mutation();

create trigger document_transmission_events_tenant_id_immutable
before update on public.document_transmission_events
for each row
execute function security.prevent_tenant_id_change();

create trigger document_transmission_events_updated_at
before update on public.document_transmission_events
for each row
execute function security.set_updated_at();

create trigger payments_document_guard
before insert or update on public.payments
for each row
execute function security.guard_payment_document();

create trigger payments_frozen
before update or delete on public.payments
for each row
execute function security.prevent_payment_mutation();

create trigger payments_open_session
before insert on public.payments
for each row
execute function security.require_open_cash_session();

create trigger payments_tenant_id_immutable
before update on public.payments
for each row
execute function security.prevent_tenant_id_change();

create trigger payments_updated_at
before update on public.payments
for each row
execute function security.set_updated_at();

create trigger payment_reversals_append_only
before update or delete on public.payment_reversals
for each row
execute function security.prevent_append_only_mutation();

create trigger payment_reversals_guard
before insert on public.payment_reversals
for each row
execute function security.guard_payment_reversal();

create trigger payment_reversals_open_session
before insert on public.payment_reversals
for each row
execute function security.require_open_cash_session();

create trigger payment_reversals_tenant_id_immutable
before update on public.payment_reversals
for each row
execute function security.prevent_tenant_id_change();

create trigger payment_reversals_updated_at
before update on public.payment_reversals
for each row
execute function security.set_updated_at();

-- RLS: la spec no la traia; el assert de catalogo de 002 la exige igual.
alter table public.documents enable row level security;
alter table public.documents force row level security;
alter table public.document_lines enable row level security;
alter table public.document_lines force row level security;
alter table public.document_line_modifiers enable row level security;
alter table public.document_line_modifiers force row level security;
alter table public.document_cancellations enable row level security;
alter table public.document_cancellations force row level security;
alter table public.document_transmission_events enable row level security;
alter table public.document_transmission_events force row level security;
alter table public.payments enable row level security;
alter table public.payments force row level security;
alter table public.payment_reversals enable row level security;
alter table public.payment_reversals force row level security;

create policy documents_select_active_members
on public.documents
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy document_lines_select_active_members
on public.document_lines
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy document_line_modifiers_select_active_members
on public.document_line_modifiers
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy document_cancellations_select_active_members
on public.document_cancellations
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy document_transmission_events_select_active_members
on public.document_transmission_events
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy payments_select_active_members
on public.payments
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy payment_reversals_select_active_members
on public.payment_reversals
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

revoke all on table public.documents from public, anon, authenticated;
grant select on table public.documents to authenticated;
revoke all on table public.document_lines from public, anon, authenticated;
grant select on table public.document_lines to authenticated;
revoke all on table public.document_line_modifiers from public, anon, authenticated;
grant select on table public.document_line_modifiers to authenticated;
revoke all on table public.document_cancellations from public, anon, authenticated;
grant select on table public.document_cancellations to authenticated;
revoke all on table public.document_transmission_events from public, anon, authenticated;
grant select on table public.document_transmission_events to authenticated;
revoke all on table public.payments from public, anon, authenticated;
grant select on table public.payments to authenticated;
revoke all on table public.payment_reversals from public, anon, authenticated;
grant select on table public.payment_reversals to authenticated;
