-- Los RPC de escritura.
--
-- El cuerpo de un SECURITY DEFINER corre como postgres, que tiene BYPASSRLS:
-- adentro no hay policy que valga. Por eso toda funcion abre derivando el
-- tenant de una fila LEIDA DEL SERVIDOR a partir de un id, y verifica membresia
-- antes de escribir una sola fila. Ninguna acepta tenant_id, user_id ni rol.
--
-- 002 suma la asercion de catalogo que hace fallar el CI si un RPC de escritura
-- futuro no trae esa guardia: se lee el cuerpo, no la cabecera.

create function security.is_tenant_member_for_transmission(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.tenant_memberships as membership
      join public.tenants as tenant on tenant.id = membership.tenant_id
      where membership.tenant_id = p_tenant_id
        and membership.user_id = auth.uid()
        and membership.status = 'active'
        and tenant.status in ('active', 'suspended')
    );
$$;

revoke all on function security.is_tenant_member_for_transmission(uuid) from public, anon, authenticated;

grant execute on function security.is_tenant_member_for_transmission(uuid) to authenticated;

-- La cuenta se ancla en una mesa (salon) o en un turno abierto (mostrador). Son
-- las dos unicas filas del servidor que dan tenant y establecimiento sin
-- aceptar un parametro de identidad, y de paso el canal deja de ser un dato que
-- el cliente pueda contradecir.
create function security.open_order(
  p_order_id uuid,
  p_dining_table_id uuid,
  p_cash_session_id uuid,
  p_code text,
  p_business_date date,
  p_opened_at timestamp with time zone,
  p_guest_count smallint,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_establishment_id uuid;
  v_channel text;
  v_existing_tenant_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  if pg_catalog.num_nonnulls(p_dining_table_id, p_cash_session_id) <> 1 then
    raise exception using
      errcode = '22023',
      message = 'an order opens against a dining table or a cash session, never both';
  end if;

  if p_dining_table_id is not null then
    select dining_table.tenant_id, dining_table.establishment_id, 'dine_in'
      into v_tenant_id, v_establishment_id, v_channel
    from public.dining_tables as dining_table
    where dining_table.id = p_dining_table_id
      and dining_table.status = 'active';
  else
    select cash_session.tenant_id, cash_session.establishment_id, 'counter'
      into v_tenant_id, v_establishment_id, v_channel
    from public.cash_sessions as cash_session
    where cash_session.id = p_cash_session_id
      and cash_session.status = 'open';
  end if;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'order anchor was not found or is not open';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  -- Idempotencia del sync. Se compara el tenant sin devolver un solo campo de la
  -- fila ajena: un uuid conocido de otro tenant no puede filtrar nada.
  select sale_order.tenant_id
    into v_existing_tenant_id
  from public.orders as sale_order
  where sale_order.id = p_order_id;

  if v_existing_tenant_id is not null then
    if v_existing_tenant_id is distinct from v_tenant_id then
      raise exception using
        errcode = 'P0001',
        message = 'order id collision';
    end if;

    return p_order_id;
  end if;

  insert into public.orders (
    id,
    tenant_id,
    establishment_id,
    channel,
    table_id,
    code,
    business_date,
    guest_count,
    note,
    opened_by_user_id,
    opened_at,
    status
  )
  values (
    p_order_id,
    v_tenant_id,
    v_establishment_id,
    v_channel,
    p_dining_table_id,
    pg_catalog.btrim(p_code),
    p_business_date,
    case when v_channel = 'dine_in' then p_guest_count else null end,
    p_note,
    v_actor_id,
    p_opened_at,
    'open'
  );

  return p_order_id;
end;
$$;

create function public.open_order(
  p_order_id uuid,
  p_dining_table_id uuid,
  p_cash_session_id uuid,
  p_code text,
  p_business_date date,
  p_opened_at timestamp with time zone,
  p_guest_count smallint,
  p_note text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.open_order(
    p_order_id,
    p_dining_table_id,
    p_cash_session_id,
    p_code,
    p_business_date,
    p_opened_at,
    p_guest_count,
    p_note
  );
$$;

revoke all on function security.open_order(uuid, uuid, uuid, text, date, timestamp with time zone, smallint, text) from public, anon, authenticated;
revoke all on function public.open_order(uuid, uuid, uuid, text, date, timestamp with time zone, smallint, text) from public, anon, authenticated;

grant execute on function security.open_order(uuid, uuid, uuid, text, date, timestamp with time zone, smallint, text) to authenticated;
grant execute on function public.open_order(uuid, uuid, uuid, text, date, timestamp with time zone, smallint, text) to authenticated;

-- Cerrar una cuenta es un acto fiscal, no un PATCH. El motivo decide el destino:
-- sin motivo se liquida (y exige comprobante por cada linea), con motivo se
-- anula (y exige que no haya ninguno emitido).
create function security.close_order(
  p_order_id uuid,
  p_closed_at timestamp with time zone,
  p_cancel_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_status text;
  v_opened_at timestamp with time zone;
  v_closed_at timestamp with time zone;
  v_target_status text;
  v_cancel_reason text;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  v_cancel_reason := pg_catalog.btrim(p_cancel_reason);

  if v_cancel_reason = '' then
    v_cancel_reason := null;
  end if;

  v_target_status := case when v_cancel_reason is null then 'settled' else 'cancelled' end;

  select sale_order.tenant_id, sale_order.status, sale_order.opened_at, sale_order.closed_at
    into v_tenant_id, v_status, v_opened_at, v_closed_at
  from public.orders as sale_order
  where sale_order.id = p_order_id
  for update;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'order was not found';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  if v_target_status = 'cancelled'
     and not security.is_tenant_member(
       v_tenant_id,
       array['owner', 'admin']::public.tenant_role[]
     ) then
    raise exception using
      errcode = '42501',
      message = 'owner or admin role is required to cancel an order';
  end if;

  -- Reintento de sync: el mismo cierre otra vez es no-op, no un error que el
  -- dispositivo no sabe distinguir de una falla real.
  if v_status <> 'open' then
    if v_status = v_target_status and v_closed_at is not distinct from p_closed_at then
      return p_order_id;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'order is already closed';
  end if;

  if p_closed_at < v_opened_at then
    raise exception using
      errcode = '22023',
      message = 'closed_at cannot precede opened_at';
  end if;

  if v_target_status = 'settled' then
    if not exists (
      select 1
      from public.order_lines as order_line
      where order_line.order_id = p_order_id
        and order_line.tenant_id = v_tenant_id
        and order_line.status = 'active'
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'order has no active lines';
    end if;

    if exists (
      select 1
      from public.order_lines as order_line
      where order_line.order_id = p_order_id
        and order_line.tenant_id = v_tenant_id
        and order_line.status = 'active'
        and not exists (
          select 1
          from public.document_lines as document_line
          join public.documents as document on document.id = document_line.document_id
          where document_line.order_line_id = order_line.id
            and document_line.tenant_id = v_tenant_id
            and document.status = 'issued'
        )
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'order cannot be settled without an issued invoice for every line';
    end if;
  else
    if exists (
      select 1
      from public.documents as document
      where document.order_id = p_order_id
        and document.tenant_id = v_tenant_id
        and document.status = 'issued'
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'order with issued documents cannot be cancelled';
    end if;
  end if;

  update public.orders as sale_order
  set status = v_target_status,
      closed_at = p_closed_at,
      closed_by_user_id = v_actor_id,
      cancel_reason = v_cancel_reason
  where sale_order.id = p_order_id
    and sale_order.tenant_id = v_tenant_id;

  return p_order_id;
end;
$$;

create function public.close_order(
  p_order_id uuid,
  p_closed_at timestamp with time zone,
  p_cancel_reason text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.close_order(p_order_id, p_closed_at, p_cancel_reason);
$$;

revoke all on function security.close_order(uuid, timestamp with time zone, text) from public, anon, authenticated;
revoke all on function public.close_order(uuid, timestamp with time zone, text) from public, anon, authenticated;

grant execute on function security.close_order(uuid, timestamp with time zone, text) to authenticated;
grant execute on function public.close_order(uuid, timestamp with time zone, text) to authenticated;

-- Numeracion, mecanismo elegido: FILA DE CONTADOR BLOQUEADA CON `for update`,
-- una fila por rango autorizado.
--
-- Por que no un sequence: nextval NO es transaccional, asi que una venta que
-- aborta quema el numero y deja el hueco que la DNIT no perdona; es un objeto
-- global que exigiria DDL en runtime por cada caja; no se reinicia por timbrado;
-- y no sabe respetar el rango autorizado.
--
-- Por que `for update` y no un advisory lock: el recurso ES la fila. El lock de
-- fila es transaccional (se libera solo al commit o al rollback), tiene
-- exactamente la granularidad del punto de expedicion y el numero se asigna en
-- la MISMA transaccion que inserta el documento: si la transaccion aborta, el
-- numero vuelve atras y no queda hueco. La fundacion usa
-- pg_advisory_xact_lock donde no hay fila que bloquear (el actor); aca la hay.
--
-- Dos cajeros simultaneos: si estan en cajas distintas son filas distintas y no
-- se tocan (cada punto de expedicion tiene su propio correlativo, que es lo que
-- pide la DNIT). Si comparten punto de expedicion, el segundo espera al commit
-- del primero. Backstop: unique (pos_terminal_id, document_type, timbrado_id,
-- number) convierte cualquier colision que se escape en 23505 y aborta todo.
--
-- Offline: el dispositivo numero sin conexion dentro de su rango cacheado y
-- manda p_number. Entonces NO se toma el rango vigente sino la fila que
-- CONTIENE ese numero, con lo que un sync tardio posterior a una renovacion de
-- rango entra igual en vez de perderse con el ticket ya entregado.
create function security.issue_document(
  p_document_id uuid,
  p_order_id uuid,
  p_cash_session_id uuid,
  p_order_line_ids uuid[],
  p_number bigint,
  p_signed_at timestamp with time zone,
  p_business_date date,
  p_buyer_doc_type text,
  p_buyer_doc_number text,
  p_buyer_ruc_dv smallint,
  p_buyer_name text,
  p_customer_id uuid
)
returns table (
  issued_document_id uuid,
  issued_number bigint,
  issued_total_gs bigint,
  was_created boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_establishment_id uuid;
  v_order_status text;
  v_pos_terminal_id uuid;
  v_establishment_code text;
  v_expedition_point_code text;
  v_counter_id uuid;
  v_timbrado_id uuid;
  v_timbrado_number text;
  v_timbrado_valid_from date;
  v_timbrado_valid_to date;
  v_range_from bigint;
  v_range_to bigint;
  v_last_number bigint;
  v_number bigint;
  v_issuer_ruc text;
  v_issuer_ruc_dv smallint;
  v_issuer_legal_name text;
  v_threshold_gs bigint;
  v_threshold_from date;
  v_buyer_doc_type text;
  v_buyer_doc_number text;
  v_buyer_ruc_dv smallint;
  v_buyer_name text;
  v_line_count smallint;
  v_total_gs bigint;
  v_discount_total_gs bigint;
  v_iva_10_gs bigint;
  v_taxable_base_10_gs bigint;
  v_iva_5_gs bigint;
  v_taxable_base_5_gs bigint;
  v_paid_gs bigint;
  v_existing_tenant_id uuid;
  v_existing_number bigint;
  v_existing_total_gs bigint;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select sale_order.tenant_id, sale_order.establishment_id, sale_order.status
    into v_tenant_id, v_establishment_id, v_order_status
  from public.orders as sale_order
  where sale_order.id = p_order_id;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'order was not found';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  -- Idempotencia ANTES de tocar el contador: un reintento no quema un segundo
  -- numero. La lectura de retorno lleva el tenant derivado, asi que un uuid de
  -- otro tenant nunca devuelve numero, total ni RUC de comprador.
  select document.tenant_id, document.number, document.total_gs
    into v_existing_tenant_id, v_existing_number, v_existing_total_gs
  from public.documents as document
  where document.id = p_document_id;

  if v_existing_tenant_id is not null then
    if v_existing_tenant_id is distinct from v_tenant_id then
      raise exception using
        errcode = 'P0001',
        message = 'document id collision';
    end if;

    return query select p_document_id, v_existing_number, v_existing_total_gs, false;
    return;
  end if;

  if v_order_status <> 'open' then
    raise exception using
      errcode = 'P0001',
      message = 'order is not open';
  end if;

  -- El turno tiene que ser del mismo local y estar abierto. De el sale la caja
  -- (punto de expedicion): pos_terminal_id nunca viene por parametro.
  select cash_session.pos_terminal_id
    into v_pos_terminal_id
  from public.cash_sessions as cash_session
  where cash_session.id = p_cash_session_id
    and cash_session.tenant_id = v_tenant_id
    and cash_session.establishment_id = v_establishment_id
    and cash_session.status = 'open';

  if v_pos_terminal_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'cash session is not open for this establishment';
  end if;

  if p_signed_at > pg_catalog.now() + interval '15 minutes'
     or p_signed_at < pg_catalog.now() - interval '30 days' then
    raise exception using
      errcode = 'P0001',
      message = 'signed_at is out of the plausible window';
  end if;

  select tenant.ruc, tenant.ruc_dv, tenant.legal_name
    into v_issuer_ruc, v_issuer_ruc_dv, v_issuer_legal_name
  from public.tenants as tenant
  where tenant.id = v_tenant_id;

  if v_issuer_ruc is null or v_issuer_ruc_dv is null or v_issuer_legal_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'issuer fiscal identity is not configured';
  end if;

  select establishment.establishment_code
    into v_establishment_code
  from public.establishments as establishment
  where establishment.id = v_establishment_id
    and establishment.tenant_id = v_tenant_id;

  if v_establishment_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'establishment code is not configured';
  end if;

  select pos_terminal.expedition_point_code
    into v_expedition_point_code
  from public.pos_terminals as pos_terminal
  where pos_terminal.id = v_pos_terminal_id
    and pos_terminal.status = 'active';

  if v_expedition_point_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'expedition point is not active';
  end if;

  if p_number is null then
    select counter.id, counter.timbrado_id, counter.range_from, counter.range_to, counter.last_number
      into v_counter_id, v_timbrado_id, v_range_from, v_range_to, v_last_number
    from public.document_counters as counter
    where counter.pos_terminal_id = v_pos_terminal_id
      and counter.document_type = 'invoice'
      and counter.status = 'active'
    for update;

    if v_counter_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'no active number range for this expedition point';
    end if;

    v_number := case when v_last_number = 0 then v_range_from else v_last_number + 1 end;

    if v_number > v_range_to then
      raise exception using
        errcode = 'P0001',
        message = 'authorized number range is exhausted';
    end if;
  else
    select counter.id, counter.timbrado_id, counter.range_from, counter.range_to, counter.last_number
      into v_counter_id, v_timbrado_id, v_range_from, v_range_to, v_last_number
    from public.document_counters as counter
    where counter.pos_terminal_id = v_pos_terminal_id
      and counter.document_type = 'invoice'
      and p_number between counter.range_from and counter.range_to
    for update;

    if v_counter_id is null then
      raise exception using
        errcode = 'P0001',
        message = 'document number outside every authorized range';
    end if;

    v_number := p_number;
  end if;

  select timbrado.number, timbrado.valid_from, timbrado.valid_to
    into v_timbrado_number, v_timbrado_valid_from, v_timbrado_valid_to
  from public.fiscal_timbrados as timbrado
  where timbrado.id = v_timbrado_id
    and timbrado.tenant_id = v_tenant_id
    and timbrado.status = 'active';

  if v_timbrado_number is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal stamp is not active';
  end if;

  if p_business_date < v_timbrado_valid_from
     or (v_timbrado_valid_to is not null and p_business_date > v_timbrado_valid_to) then
    raise exception using
      errcode = 'P0001',
      message = 'business date is outside the fiscal stamp validity';
  end if;

  -- El umbral se resuelve por la FECHA DE LA VENTA, jamas por now(): con 72 h de
  -- ventana, sincronizar despues de un decreto es el caso normal.
  select threshold.anonymous_buyer_threshold_gs, threshold.effective_from
    into v_threshold_gs, v_threshold_from
  from public.fiscal_thresholds as threshold
  where threshold.tenant_id = v_tenant_id
    and threshold.effective_from <= p_business_date
    and (threshold.effective_to is null or p_business_date < threshold.effective_to)
  order by threshold.effective_from desc
  limit 1;

  if v_threshold_gs is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal threshold is not configured';
  end if;

  if p_order_line_ids is null or pg_catalog.array_length(p_order_line_ids, 1) is null then
    raise exception using
      errcode = '22023',
      message = 'a document needs at least one line';
  end if;

  if pg_catalog.array_length(p_order_line_ids, 1) <> (
    select pg_catalog.count(distinct requested.order_line_id)
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
  ) then
    raise exception using
      errcode = '22023',
      message = 'duplicated order line in the document';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
    where not exists (
      select 1
      from public.order_lines as order_line
      where order_line.id = requested.order_line_id
        and order_line.order_id = p_order_id
        and order_line.tenant_id = v_tenant_id
        and order_line.status = 'active'
    )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'order line does not belong to this open order';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
    join public.order_lines as order_line on order_line.id = requested.order_line_id
    where exists (
      select 1
      from public.document_lines as document_line
      where document_line.order_line_id = order_line.id
        and document_line.tenant_id = v_tenant_id
    )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'order line was already invoiced';
  end if;

  -- La tasa de IVA es la unica cifra que la DNIT audita: se resuelve contra el
  -- catalogo y la divergencia se RECHAZA, no se corrige en silencio.
  if exists (
    select 1
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
    join public.order_lines as order_line on order_line.id = requested.order_line_id
    join public.products as product on product.id = order_line.product_id
    where product.iva_rate is distinct from order_line.iva_rate
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'line iva rate does not match product iva rate';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
    join public.order_lines as order_line on order_line.id = requested.order_line_id
    where order_line.modifiers_total_gs is distinct from (
      select coalesce(pg_catalog.sum(modifier.price_delta_gs), 0)
      from public.order_line_modifiers as modifier
      where modifier.order_line_id = order_line.id
        and modifier.status = 'active'
    )
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'order line modifiers do not add up';
  end if;

  select
    pg_catalog.count(*)::smallint,
    pg_catalog.sum(frozen.line_total_gs),
    pg_catalog.sum(frozen.discount_gs),
    pg_catalog.sum(case when frozen.iva_rate = 10 then frozen.iva_amount_gs else 0 end),
    pg_catalog.sum(case when frozen.iva_rate = 10 then frozen.line_total_gs - frozen.iva_amount_gs else 0 end),
    pg_catalog.sum(case when frozen.iva_rate = 5 then frozen.iva_amount_gs else 0 end),
    pg_catalog.sum(case when frozen.iva_rate = 5 then frozen.line_total_gs - frozen.iva_amount_gs else 0 end)
    into
      v_line_count,
      v_total_gs,
      v_discount_total_gs,
      v_iva_10_gs,
      v_taxable_base_10_gs,
      v_iva_5_gs,
      v_taxable_base_5_gs
  from (
    select
      order_line.line_total_gs,
      order_line.discount_gs,
      order_line.iva_rate,
      pg_catalog.round(
        (order_line.line_total_gs::numeric * order_line.iva_rate)
        / (100 + order_line.iva_rate)
      )::bigint as iva_amount_gs
    from pg_catalog.unnest(p_order_line_ids) as requested(order_line_id)
    join public.order_lines as order_line on order_line.id = requested.order_line_id
  ) as frozen;

  if v_total_gs <= 0 then
    raise exception using
      errcode = 'P0001',
      message = 'document total must be positive';
  end if;

  v_buyer_doc_type := p_buyer_doc_type;
  v_buyer_doc_number := pg_catalog.btrim(p_buyer_doc_number);
  v_buyer_ruc_dv := p_buyer_ruc_dv;
  v_buyer_name := pg_catalog.btrim(p_buyer_name);

  if v_buyer_doc_number = '' then
    v_buyer_doc_number := null;
  end if;

  if v_buyer_name = '' then
    v_buyer_name := null;
  end if;

  -- El cliente aporta la referencia; el comprobante congela la COPIA, porque un
  -- cliente se edita despues y una factura entregada no.
  if p_customer_id is not null then
    if v_buyer_doc_number is null then
      select customer.doc_type, customer.doc_number, customer.ruc_dv, customer.name
        into v_buyer_doc_type, v_buyer_doc_number, v_buyer_ruc_dv, v_buyer_name
      from public.customers as customer
      where customer.id = p_customer_id
        and customer.tenant_id = v_tenant_id;
    elsif not exists (
      select 1
      from public.customers as customer
      where customer.id = p_customer_id
        and customer.tenant_id = v_tenant_id
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'customer was not found';
    end if;
  end if;

  if v_total_gs > v_threshold_gs and v_buyer_doc_number is null then
    raise exception using
      errcode = 'P0001',
      message = 'buyer identification is required above the anonymous threshold';
  end if;

  if v_buyer_doc_number is not null
     and (v_buyer_name is null or pg_catalog.char_length(v_buyer_name) < 3) then
    raise exception using
      errcode = '22023',
      message = 'buyer name is required with a buyer document';
  end if;

  if v_buyer_doc_type = 'RUC' and v_buyer_ruc_dv is null then
    raise exception using
      errcode = '22023',
      message = 'buyer ruc check digit is required';
  end if;

  -- PY-QR necesita el numero de factura (62-01) antes de mostrar el codigo, y el
  -- cobro QR nace 'pending' hasta que confirma el adquirente: la cobertura se
  -- valida con los cobros vivos, no solo con los confirmados.
  select coalesce(pg_catalog.sum(payment.amount_gs), 0)
    into v_paid_gs
  from public.payments as payment
  where payment.order_id = p_order_id
    and payment.tenant_id = v_tenant_id
    and payment.document_id is null
    and payment.status in ('pending', 'confirmed');

  if v_paid_gs <> v_total_gs then
    raise exception using
      errcode = 'P0001',
      message = 'payments do not cover the document total';
  end if;

  insert into public.documents (
    id,
    tenant_id,
    establishment_id,
    pos_terminal_id,
    cash_session_id,
    timbrado_id,
    order_id,
    customer_id,
    document_type,
    establishment_code,
    expedition_point_code,
    timbrado_number,
    timbrado_valid_from,
    timbrado_valid_to,
    number,
    authorized_range_from,
    authorized_range_to,
    issuer_ruc,
    issuer_ruc_dv,
    issuer_legal_name,
    buyer_doc_type,
    buyer_doc_number,
    buyer_ruc_dv,
    buyer_name,
    anonymous_buyer_threshold_gs,
    anonymous_threshold_from,
    total_gs,
    discount_total_gs,
    taxable_base_10_gs,
    iva_10_gs,
    taxable_base_5_gs,
    iva_5_gs,
    line_count,
    business_date,
    signed_at,
    sifen_status,
    status
  )
  values (
    p_document_id,
    v_tenant_id,
    v_establishment_id,
    v_pos_terminal_id,
    p_cash_session_id,
    v_timbrado_id,
    p_order_id,
    p_customer_id,
    'invoice',
    v_establishment_code,
    v_expedition_point_code,
    v_timbrado_number,
    v_timbrado_valid_from,
    v_timbrado_valid_to,
    v_number,
    v_range_from,
    v_range_to,
    v_issuer_ruc,
    v_issuer_ruc_dv,
    v_issuer_legal_name,
    v_buyer_doc_type,
    v_buyer_doc_number,
    v_buyer_ruc_dv,
    v_buyer_name,
    v_threshold_gs,
    v_threshold_from,
    v_total_gs,
    v_discount_total_gs,
    v_taxable_base_10_gs,
    v_iva_10_gs,
    v_taxable_base_5_gs,
    v_iva_5_gs,
    v_line_count,
    p_business_date,
    p_signed_at,
    'pending',
    'issued'
  );

  insert into public.document_lines (
    tenant_id,
    document_id,
    document_type,
    order_line_id,
    product_id,
    line_number,
    product_name,
    product_category_name,
    quantity,
    unit_price_gs,
    modifiers_total_gs,
    discount_gs,
    iva_rate,
    taxable_base_gs,
    iva_amount_gs,
    line_total_gs
  )
  select
    v_tenant_id,
    p_document_id,
    'invoice',
    order_line.id,
    order_line.product_id,
    requested.ordinal::smallint,
    order_line.product_name,
    category.name,
    order_line.quantity,
    order_line.unit_price_gs,
    order_line.modifiers_total_gs,
    order_line.discount_gs,
    order_line.iva_rate,
    order_line.line_total_gs
      - pg_catalog.round(
          (order_line.line_total_gs::numeric * order_line.iva_rate)
          / (100 + order_line.iva_rate)
        )::bigint,
    pg_catalog.round(
      (order_line.line_total_gs::numeric * order_line.iva_rate)
      / (100 + order_line.iva_rate)
    )::bigint,
    order_line.line_total_gs
  from pg_catalog.unnest(p_order_line_ids) with ordinality as requested(order_line_id, ordinal)
  join public.order_lines as order_line on order_line.id = requested.order_line_id
  join public.products as product on product.id = order_line.product_id
  join public.product_categories as category on category.id = product.category_id;

  -- display_order se REASIGNA 1..n por linea desde el pedido: 'doble queso' son
  -- dos filas que nacen ambas con display_order 0 y colisionarian contra la
  -- unique del comprobante justo con el cliente en la caja.
  insert into public.document_line_modifiers (
    tenant_id,
    document_line_id,
    modifier_option_id,
    modifier_group_name,
    name,
    price_delta_gs,
    display_order
  )
  select
    v_tenant_id,
    document_line.id,
    modifier.modifier_option_id,
    modifier.modifier_group_name,
    modifier.name,
    modifier.price_delta_gs,
    (
      pg_catalog.row_number() over (
        partition by document_line.id
        order by modifier.display_order, modifier.created_at, modifier.id
      )
    )::smallint
  from public.document_lines as document_line
  join public.order_line_modifiers as modifier
    on modifier.order_line_id = document_line.order_line_id
  where document_line.document_id = p_document_id
    and document_line.tenant_id = v_tenant_id
    and modifier.status = 'active';

  update public.document_counters as counter
  set last_number = case when counter.last_number > v_number then counter.last_number else v_number end,
      status = case
        when counter.status = 'active' and v_number >= counter.range_to then 'exhausted'
        else counter.status
      end
  where counter.id = v_counter_id;

  update public.payments as payment
  set document_id = p_document_id
  where payment.order_id = p_order_id
    and payment.tenant_id = v_tenant_id
    and payment.document_id is null
    and payment.status in ('pending', 'confirmed');

  return query select p_document_id, v_number, v_total_gs, true;
end;
$$;

create function public.issue_document(
  p_document_id uuid,
  p_order_id uuid,
  p_cash_session_id uuid,
  p_order_line_ids uuid[],
  p_number bigint,
  p_signed_at timestamp with time zone,
  p_business_date date,
  p_buyer_doc_type text,
  p_buyer_doc_number text,
  p_buyer_ruc_dv smallint,
  p_buyer_name text,
  p_customer_id uuid
)
returns table (
  issued_document_id uuid,
  issued_number bigint,
  issued_total_gs bigint,
  was_created boolean
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from security.issue_document(
    p_document_id,
    p_order_id,
    p_cash_session_id,
    p_order_line_ids,
    p_number,
    p_signed_at,
    p_business_date,
    p_buyer_doc_type,
    p_buyer_doc_number,
    p_buyer_ruc_dv,
    p_buyer_name,
    p_customer_id
  );
$$;

revoke all on function security.issue_document(uuid, uuid, uuid, uuid[], bigint, timestamp with time zone, date, text, text, smallint, text, uuid) from public, anon, authenticated;
revoke all on function public.issue_document(uuid, uuid, uuid, uuid[], bigint, timestamp with time zone, date, text, text, smallint, text, uuid) from public, anon, authenticated;

grant execute on function security.issue_document(uuid, uuid, uuid, uuid[], bigint, timestamp with time zone, date, text, text, smallint, text, uuid) to authenticated;
grant execute on function public.issue_document(uuid, uuid, uuid, uuid[], bigint, timestamp with time zone, date, text, text, smallint, text, uuid) to authenticated;

-- El turno cerrado no recibe plata: el arqueo congelado y la pantalla de cierre
-- se contradecirian sin ninguna fila que lo explique.
create function security.register_payment(
  p_payment_id uuid,
  p_order_id uuid,
  p_cash_session_id uuid,
  p_method text,
  p_amount_gs bigint,
  p_tip_gs bigint,
  p_tendered_gs bigint,
  p_change_gs bigint,
  p_external_reference text,
  p_occurred_at timestamp with time zone,
  p_business_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_establishment_id uuid;
  v_order_status text;
  v_pos_terminal_id uuid;
  v_status text;
  v_external_reference text;
  v_existing_tenant_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select sale_order.tenant_id, sale_order.establishment_id, sale_order.status
    into v_tenant_id, v_establishment_id, v_order_status
  from public.orders as sale_order
  where sale_order.id = p_order_id;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'order was not found';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  select payment.tenant_id
    into v_existing_tenant_id
  from public.payments as payment
  where payment.id = p_payment_id;

  if v_existing_tenant_id is not null then
    if v_existing_tenant_id is distinct from v_tenant_id then
      raise exception using
        errcode = 'P0001',
        message = 'payment id collision';
    end if;

    return p_payment_id;
  end if;

  if v_order_status <> 'open' then
    raise exception using
      errcode = 'P0001',
      message = 'order is not open';
  end if;

  if p_amount_gs is null or p_amount_gs <= 0 then
    raise exception using
      errcode = '22023',
      message = 'payment amount must be positive';
  end if;

  select cash_session.pos_terminal_id
    into v_pos_terminal_id
  from public.cash_sessions as cash_session
  where cash_session.id = p_cash_session_id
    and cash_session.tenant_id = v_tenant_id
    and cash_session.establishment_id = v_establishment_id
    and cash_session.status = 'open';

  if v_pos_terminal_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'cash session is not open for this establishment';
  end if;

  v_external_reference := pg_catalog.btrim(p_external_reference);

  if v_external_reference = '' then
    v_external_reference := null;
  end if;

  v_status := case when p_method in ('qr', 'transfer') then 'pending' else 'confirmed' end;

  insert into public.payments (
    id,
    tenant_id,
    establishment_id,
    order_id,
    pos_terminal_id,
    cash_session_id,
    method,
    amount_gs,
    tip_gs,
    tendered_gs,
    change_gs,
    external_reference,
    occurred_at,
    business_date,
    created_by_user_id,
    status
  )
  values (
    p_payment_id,
    v_tenant_id,
    v_establishment_id,
    p_order_id,
    v_pos_terminal_id,
    p_cash_session_id,
    p_method,
    p_amount_gs,
    coalesce(p_tip_gs, 0),
    p_tendered_gs,
    coalesce(p_change_gs, 0),
    v_external_reference,
    p_occurred_at,
    p_business_date,
    v_actor_id,
    v_status
  );

  return p_payment_id;
end;
$$;

create function public.register_payment(
  p_payment_id uuid,
  p_order_id uuid,
  p_cash_session_id uuid,
  p_method text,
  p_amount_gs bigint,
  p_tip_gs bigint,
  p_tendered_gs bigint,
  p_change_gs bigint,
  p_external_reference text,
  p_occurred_at timestamp with time zone,
  p_business_date date
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.register_payment(
    p_payment_id,
    p_order_id,
    p_cash_session_id,
    p_method,
    p_amount_gs,
    p_tip_gs,
    p_tendered_gs,
    p_change_gs,
    p_external_reference,
    p_occurred_at,
    p_business_date
  );
$$;

revoke all on function security.register_payment(uuid, uuid, uuid, text, bigint, bigint, bigint, bigint, text, timestamp with time zone, date) from public, anon, authenticated;
revoke all on function public.register_payment(uuid, uuid, uuid, text, bigint, bigint, bigint, bigint, text, timestamp with time zone, date) from public, anon, authenticated;

grant execute on function security.register_payment(uuid, uuid, uuid, text, bigint, bigint, bigint, bigint, text, timestamp with time zone, date) to authenticated;
grant execute on function public.register_payment(uuid, uuid, uuid, text, bigint, bigint, bigint, bigint, text, timestamp with time zone, date) to authenticated;

create function security.record_transmission_result(
  p_document_id uuid,
  p_cancellation_id uuid,
  p_outcome text,
  p_response_code text,
  p_response_message text,
  p_request_payload_hash text,
  p_cdc text,
  p_transmitted_at timestamp with time zone
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_current_status text;
  v_subject_document_id uuid;
  v_next_status text;
  v_attempt_number smallint;
  v_event_id uuid := pg_catalog.gen_random_uuid();
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  if pg_catalog.num_nonnulls(p_document_id, p_cancellation_id) <> 1 then
    raise exception using
      errcode = '22023',
      message = 'a transmission event belongs to a document or to a cancellation, never both';
  end if;

  if p_document_id is not null then
    select document.tenant_id, document.sifen_status
      into v_tenant_id, v_current_status
    from public.documents as document
    where document.id = p_document_id
    for update;
  else
    select cancellation.tenant_id, cancellation.sifen_status, cancellation.document_id
      into v_tenant_id, v_current_status, v_subject_document_id
    from public.document_cancellations as cancellation
    where cancellation.id = p_cancellation_id
    for update;
  end if;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'transmission subject was not found';
  end if;

  -- Deber fiscal, no acceso comercial: la suspension frena la venta, no la
  -- obligacion de transmitir dentro de las 72 h.
  if not security.is_tenant_member_for_transmission(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  v_next_status := case
    when p_outcome = 'approved' then 'approved'
    when p_outcome = 'rejected' then 'rejected'
    else 'pending'
  end;

  if v_current_status = 'approved' and v_next_status <> 'approved' then
    raise exception using
      errcode = 'P0001',
      message = 'approved document cannot regress';
  end if;

  if p_document_id is not null then
    select coalesce(pg_catalog.max(event.attempt_number), 0)::smallint + 1
      into v_attempt_number
    from public.document_transmission_events as event
    where event.document_id = p_document_id
      and event.tenant_id = v_tenant_id;
  else
    select coalesce(pg_catalog.max(event.attempt_number), 0)::smallint + 1
      into v_attempt_number
    from public.document_transmission_events as event
    where event.document_cancellation_id = p_cancellation_id
      and event.tenant_id = v_tenant_id;
  end if;

  insert into public.document_transmission_events (
    id,
    tenant_id,
    document_id,
    document_cancellation_id,
    attempt_number,
    outcome,
    response_code,
    response_message,
    request_payload_hash,
    transmitted_at
  )
  values (
    v_event_id,
    v_tenant_id,
    p_document_id,
    p_cancellation_id,
    v_attempt_number,
    p_outcome,
    p_response_code,
    p_response_message,
    p_request_payload_hash,
    p_transmitted_at
  );

  if p_document_id is not null then
    update public.documents as document
    set sifen_status = v_next_status,
        transmitted_at = case when v_next_status = 'pending' then null else p_transmitted_at end,
        sifen_response_code = p_response_code,
        sifen_response_message = p_response_message,
        transmit_attempts = v_attempt_number,
        cdc = case when p_cdc is null then document.cdc else p_cdc end
    where document.id = p_document_id
      and document.tenant_id = v_tenant_id;
  else
    update public.document_cancellations as cancellation
    set sifen_status = v_next_status,
        transmitted_at = case when v_next_status = 'pending' then null else p_transmitted_at end,
        sifen_response_code = p_response_code,
        transmit_attempts = v_attempt_number
    where cancellation.id = p_cancellation_id
      and cancellation.tenant_id = v_tenant_id;

    -- La proyeccion 'cancelled' del documento solo la mueve la APROBACION de
    -- SIFEN, nunca el pedido de anulacion.
    if v_next_status = 'approved' then
      update public.documents as document
      set status = 'cancelled'
      where document.id = v_subject_document_id
        and document.tenant_id = v_tenant_id;
    end if;
  end if;

  return v_event_id;
end;
$$;

create function public.record_transmission_result(
  p_document_id uuid,
  p_cancellation_id uuid,
  p_outcome text,
  p_response_code text,
  p_response_message text,
  p_request_payload_hash text,
  p_cdc text,
  p_transmitted_at timestamp with time zone
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.record_transmission_result(
    p_document_id,
    p_cancellation_id,
    p_outcome,
    p_response_code,
    p_response_message,
    p_request_payload_hash,
    p_cdc,
    p_transmitted_at
  );
$$;

revoke all on function security.record_transmission_result(uuid, uuid, text, text, text, text, text, timestamp with time zone) from public, anon, authenticated;
revoke all on function public.record_transmission_result(uuid, uuid, text, text, text, text, text, timestamp with time zone) from public, anon, authenticated;

grant execute on function security.record_transmission_result(uuid, uuid, text, text, text, text, text, timestamp with time zone) to authenticated;
grant execute on function public.record_transmission_result(uuid, uuid, text, text, text, text, text, timestamp with time zone) to authenticated;

create function security.cancel_document(
  p_cancellation_id uuid,
  p_document_id uuid,
  p_reason text,
  p_requested_at timestamp with time zone
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_document_status text;
  v_signed_at timestamp with time zone;
  v_reason text;
  v_existing_tenant_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select document.tenant_id, document.status, document.signed_at
    into v_tenant_id, v_document_status, v_signed_at
  from public.documents as document
  where document.id = p_document_id;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'document was not found';
  end if;

  if not security.is_tenant_member(
    v_tenant_id,
    array['owner', 'admin']::public.tenant_role[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'owner or admin role is required to cancel a document';
  end if;

  select cancellation.tenant_id
    into v_existing_tenant_id
  from public.document_cancellations as cancellation
  where cancellation.id = p_cancellation_id;

  if v_existing_tenant_id is not null then
    if v_existing_tenant_id is distinct from v_tenant_id then
      raise exception using
        errcode = 'P0001',
        message = 'cancellation id collision';
    end if;

    return p_cancellation_id;
  end if;

  if v_document_status <> 'issued' then
    raise exception using
      errcode = 'P0001',
      message = 'document is not issued';
  end if;

  if p_requested_at < v_signed_at then
    raise exception using
      errcode = '22023',
      message = 'requested_at cannot precede the document signature';
  end if;

  v_reason := pg_catalog.btrim(p_reason);

  if v_reason is null or pg_catalog.char_length(v_reason) < 10 then
    raise exception using
      errcode = '22023',
      message = 'cancellation reason must be at least 10 characters';
  end if;

  -- Un rechazo de SIFEN tiene que dejar reintentar con el motivo corregido; dos
  -- anulaciones vivas del mismo comprobante, no.
  if exists (
    select 1
    from public.document_cancellations as cancellation
    where cancellation.document_id = p_document_id
      and cancellation.tenant_id = v_tenant_id
      and cancellation.sifen_status in ('pending', 'transmitted', 'approved')
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'document already has an open cancellation';
  end if;

  insert into public.document_cancellations (
    id,
    tenant_id,
    document_id,
    reason,
    requested_at,
    requested_by_user_id,
    sifen_status
  )
  values (
    p_cancellation_id,
    v_tenant_id,
    p_document_id,
    v_reason,
    p_requested_at,
    v_actor_id,
    'pending'
  );

  return p_cancellation_id;
end;
$$;

create function public.cancel_document(
  p_cancellation_id uuid,
  p_document_id uuid,
  p_reason text,
  p_requested_at timestamp with time zone
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.cancel_document(p_cancellation_id, p_document_id, p_reason, p_requested_at);
$$;

revoke all on function security.cancel_document(uuid, uuid, text, timestamp with time zone) from public, anon, authenticated;
revoke all on function public.cancel_document(uuid, uuid, text, timestamp with time zone) from public, anon, authenticated;

grant execute on function security.cancel_document(uuid, uuid, text, timestamp with time zone) to authenticated;
grant execute on function public.cancel_document(uuid, uuid, text, timestamp with time zone) to authenticated;

-- security.assign_number_range ya la crea la migracion de configuracion fiscal; no se redeclara.

create function security.open_cash_session(
  p_cash_session_id uuid,
  p_expedition_point_id uuid,
  p_business_date date,
  p_opened_at timestamp with time zone,
  p_opening_float_gs bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_establishment_id uuid;
  v_existing_tenant_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select pos_terminal.tenant_id, pos_terminal.establishment_id
    into v_tenant_id, v_establishment_id
  from public.pos_terminals as pos_terminal
  where pos_terminal.id = p_expedition_point_id
    and pos_terminal.status = 'active';

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'expedition point is not active';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  select cash_session.tenant_id
    into v_existing_tenant_id
  from public.cash_sessions as cash_session
  where cash_session.id = p_cash_session_id;

  if v_existing_tenant_id is not null then
    if v_existing_tenant_id is distinct from v_tenant_id then
      raise exception using
        errcode = 'P0001',
        message = 'cash session id collision';
    end if;

    return p_cash_session_id;
  end if;

  if exists (
    select 1
    from public.cash_sessions as cash_session
    where cash_session.pos_terminal_id = p_expedition_point_id
      and cash_session.status = 'open'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'expedition point already has an open cash session';
  end if;

  insert into public.cash_sessions (
    id,
    tenant_id,
    establishment_id,
    pos_terminal_id,
    business_date,
    opened_by_user_id,
    opened_at,
    opening_float_gs,
    status
  )
  values (
    p_cash_session_id,
    v_tenant_id,
    v_establishment_id,
    p_expedition_point_id,
    p_business_date,
    v_actor_id,
    p_opened_at,
    coalesce(p_opening_float_gs, 0),
    'open'
  );

  return p_cash_session_id;
end;
$$;

create function public.open_cash_session(
  p_cash_session_id uuid,
  p_expedition_point_id uuid,
  p_business_date date,
  p_opened_at timestamp with time zone,
  p_opening_float_gs bigint
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.open_cash_session(
    p_cash_session_id,
    p_expedition_point_id,
    p_business_date,
    p_opened_at,
    p_opening_float_gs
  );
$$;

revoke all on function security.open_cash_session(uuid, uuid, date, timestamp with time zone, bigint) from public, anon, authenticated;
revoke all on function public.open_cash_session(uuid, uuid, date, timestamp with time zone, bigint) from public, anon, authenticated;

grant execute on function security.open_cash_session(uuid, uuid, date, timestamp with time zone, bigint) to authenticated;
grant execute on function public.open_cash_session(uuid, uuid, date, timestamp with time zone, bigint) to authenticated;

create function security.close_cash_session(
  p_cash_session_id uuid,
  p_counted_cash_gs bigint,
  p_closed_at timestamp with time zone,
  p_closing_note text
)
returns table (
  closing_expected_gs bigint,
  closing_counted_gs bigint,
  closing_difference_gs bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_status text;
  v_opened_at timestamp with time zone;
  v_opened_by_user_id uuid;
  v_opening_float_gs bigint;
  v_frozen_expected_gs bigint;
  v_frozen_counted_gs bigint;
  v_cash_received_gs bigint;
  v_cash_reversed_gs bigint;
  v_cash_in_gs bigint;
  v_cash_out_gs bigint;
  v_expected_gs bigint;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select
    cash_session.tenant_id,
    cash_session.status,
    cash_session.opened_at,
    cash_session.opened_by_user_id,
    cash_session.opening_float_gs,
    cash_session.expected_cash_gs,
    cash_session.counted_cash_gs
    into
      v_tenant_id,
      v_status,
      v_opened_at,
      v_opened_by_user_id,
      v_opening_float_gs,
      v_frozen_expected_gs,
      v_frozen_counted_gs
  from public.cash_sessions as cash_session
  where cash_session.id = p_cash_session_id
  for update;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'cash session was not found';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  if v_opened_by_user_id is distinct from v_actor_id
     and not security.is_tenant_member(
       v_tenant_id,
       array['owner', 'admin']::public.tenant_role[]
     ) then
    raise exception using
      errcode = '42501',
      message = 'only the cashier who opened the shift or an admin can close it';
  end if;

  if v_status = 'closed' then
    if v_frozen_counted_gs is not distinct from p_counted_cash_gs then
      return query select
        v_frozen_expected_gs,
        v_frozen_counted_gs,
        v_frozen_counted_gs - v_frozen_expected_gs;
      return;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'cash session is already closed';
  end if;

  if p_counted_cash_gs is null or p_counted_cash_gs < 0 then
    raise exception using
      errcode = '22023',
      message = 'counted cash must be provided';
  end if;

  if p_closed_at < v_opened_at then
    raise exception using
      errcode = '22023',
      message = 'closed_at cannot precede opened_at';
  end if;

  -- charged_total_gs y no amount_gs: la propina en efectivo tambien entra al
  -- cajon. El vuelto ya esta neteado, porque tendered = amount + tip + change.
  select coalesce(pg_catalog.sum(payment.charged_total_gs), 0)
    into v_cash_received_gs
  from public.payments as payment
  where payment.cash_session_id = p_cash_session_id
    and payment.tenant_id = v_tenant_id
    and payment.method = 'cash'
    and payment.status = 'confirmed';

  select coalesce(pg_catalog.sum(payment.charged_total_gs), 0)
    into v_cash_reversed_gs
  from public.payment_reversals as reversal
  join public.payments as payment on payment.id = reversal.payment_id
  where reversal.cash_session_id = p_cash_session_id
    and reversal.tenant_id = v_tenant_id
    and payment.method = 'cash';

  select coalesce(pg_catalog.sum(movement.amount_gs), 0)
    into v_cash_in_gs
  from public.cash_movements as movement
  where movement.cash_session_id = p_cash_session_id
    and movement.tenant_id = v_tenant_id
    and movement.movement_type = 'cash_in';

  select coalesce(pg_catalog.sum(movement.amount_gs), 0)
    into v_cash_out_gs
  from public.cash_movements as movement
  where movement.cash_session_id = p_cash_session_id
    and movement.tenant_id = v_tenant_id
    and movement.movement_type in ('cash_out', 'vault_drop', 'supplier_payout');

  v_expected_gs := v_opening_float_gs
    + v_cash_received_gs
    - v_cash_reversed_gs
    + v_cash_in_gs
    - v_cash_out_gs;

  update public.cash_sessions as cash_session
  set status = 'closed',
      closed_at = p_closed_at,
      closed_by_user_id = v_actor_id,
      counted_cash_gs = p_counted_cash_gs,
      expected_cash_gs = v_expected_gs,
      closing_note = pg_catalog.btrim(p_closing_note)
  where cash_session.id = p_cash_session_id
    and cash_session.tenant_id = v_tenant_id;

  return query select
    v_expected_gs,
    p_counted_cash_gs,
    p_counted_cash_gs - v_expected_gs;
end;
$$;

create function public.close_cash_session(
  p_cash_session_id uuid,
  p_counted_cash_gs bigint,
  p_closed_at timestamp with time zone,
  p_closing_note text
)
returns table (
  closing_expected_gs bigint,
  closing_counted_gs bigint,
  closing_difference_gs bigint
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from security.close_cash_session(
    p_cash_session_id,
    p_counted_cash_gs,
    p_closed_at,
    p_closing_note
  );
$$;

revoke all on function security.close_cash_session(uuid, bigint, timestamp with time zone, text) from public, anon, authenticated;
revoke all on function public.close_cash_session(uuid, bigint, timestamp with time zone, text) from public, anon, authenticated;

grant execute on function security.close_cash_session(uuid, bigint, timestamp with time zone, text) to authenticated;
grant execute on function public.close_cash_session(uuid, bigint, timestamp with time zone, text) to authenticated;

