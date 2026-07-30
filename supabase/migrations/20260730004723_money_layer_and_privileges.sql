-- La capa de plata y dos privilegios de mas.
--
-- Todo lo de aca sale de la review. Cinco cosas:
--
-- 1. authenticated tenia UPDATE de tabla completa sobre tenants, incluida status,
--    que es de plataforma y no del inquilino. Como is_tenant_member exige
--    tenant.status = 'active', un admin podia suspender su propio tenant y la
--    policy que permitiria revertirlo dejaba de aplicar: viaje de ida. Pasa a
--    grant de columna, igual que orders, donde el cierre ya se saco del grant.
--
-- 2. Un reverso de efectivo del MISMO turno se restaba dos veces del esperado: el
--    cobro salia de la suma de 'confirmed' y ademas se le restaba por reverso.
--    El arqueo mentia por el monto del cobro.
--
-- 3. Los movimientos 'correction' no entraban en ninguna de las dos sumas del
--    arqueo y el tipo no tenia signo: no habia forma de decir si la correccion
--    puso o saco plata. Se parte en correction_in y correction_out.
--
-- 4. Un cobro con QR o transferencia nacia 'pending' y no existia ningun camino
--    para confirmarlo: ni grant, ni policy, ni RPC. Igual cubria la factura y el
--    turno cerraba sin ver que la plata nunca se confirmo.
--
-- 5. El reverso de cobro no tenia camino: payment_reversals era inalcanzable
--    desde authenticated, asi que un cobro duplicado dejaba la cuenta muerta.

-- ============================================================
-- 1. tenants: status sale de PostgREST
-- ============================================================
revoke update on table public.tenants from authenticated;
grant update (name, legal_name) on table public.tenants to authenticated;

-- ============================================================
-- 3. La correccion de caja lleva signo
-- ============================================================
alter table public.cash_movements
  drop constraint cash_movements_movement_type_check,
  drop constraint cash_movements_correction_check;

alter table public.cash_movements
  add constraint cash_movements_movement_type_check
    check (
      movement_type in (
        'cash_in',
        'cash_out',
        'vault_drop',
        'supplier_payout',
        'correction_in',
        'correction_out'
      )
    ),
  add constraint cash_movements_correction_check
    check (
      (movement_type in ('correction_in', 'correction_out'))
      = (adjusts_cash_session_id is not null)
    );

-- ============================================================
-- 4. Confirmar un cobro que nacio pendiente
-- ============================================================
create function security.confirm_payment(
  p_payment_id uuid,
  p_external_reference text,
  p_external_confirmed_at timestamp with time zone
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
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select payment.tenant_id, payment.status
    into v_tenant_id, v_status
  from public.payments as payment
  where payment.id = p_payment_id
  for update;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'payment was not found';
  end if;

  if not security.is_tenant_member(v_tenant_id) then
    raise exception using
      errcode = '42501',
      message = 'active tenant membership is required';
  end if;

  if v_status <> 'pending' then
    raise exception using
      errcode = 'P0001',
      message = 'only a pending payment can be confirmed';
  end if;

  update public.payments as payment
  set status = 'confirmed',
      external_reference = p_external_reference,
      external_confirmed_at = coalesce(p_external_confirmed_at, pg_catalog.now())
  where payment.id = p_payment_id
    and payment.tenant_id = v_tenant_id;

  return p_payment_id;
end;
$$;

create function public.confirm_payment(
  p_payment_id uuid,
  p_external_reference text,
  p_external_confirmed_at timestamp with time zone
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.confirm_payment(
    p_payment_id,
    p_external_reference,
    p_external_confirmed_at
  );
$$;

-- ============================================================
-- 5. Revertir un cobro
-- ============================================================
create function security.reverse_payment(
  p_reversal_id uuid,
  p_payment_id uuid,
  p_cash_session_id uuid,
  p_reason text,
  p_reversed_at timestamp with time zone
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
  v_session_tenant_id uuid;
  v_session_status text;
  v_reason text;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  select payment.tenant_id, payment.status
    into v_tenant_id, v_status
  from public.payments as payment
  where payment.id = p_payment_id
  for update;

  if v_tenant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'payment was not found';
  end if;

  -- Plata que sale del cajon es acto de owner o admin, igual que una sangria.
  if not security.is_tenant_member(
       v_tenant_id,
       array['owner', 'admin']::public.tenant_role[]
     ) then
    raise exception using
      errcode = '42501',
      message = 'owner or admin role is required to reverse a payment';
  end if;

  if v_status = 'reversed' then
    raise exception using
      errcode = 'P0001',
      message = 'payment was already reversed';
  end if;

  v_reason := pg_catalog.btrim(p_reason);

  if v_reason is null or v_reason = '' then
    raise exception using
      errcode = '22023',
      message = 'a reversal reason is required';
  end if;

  -- El reverso pertenece al turno en el que OCURRE, que puede ser posterior al
  -- del cobro. Sin eso, devolver hoy la plata de ayer descuadraba un arqueo ya
  -- cerrado sin dejar rastro de donde salio.
  select cash_session.tenant_id, cash_session.status
    into v_session_tenant_id, v_session_status
  from public.cash_sessions as cash_session
  where cash_session.id = p_cash_session_id;

  if v_session_tenant_id is distinct from v_tenant_id then
    raise exception using
      errcode = '42501',
      message = 'cash session belongs to another tenant';
  end if;

  if v_session_status <> 'open' then
    raise exception using
      errcode = 'P0001',
      message = 'a reversal must be registered in an open cash session';
  end if;

  -- Primero la fila del reverso: el guardian del cobro exige que exista antes de
  -- aceptar status = 'reversed'.
  insert into public.payment_reversals (
    id,
    tenant_id,
    payment_id,
    cash_session_id,
    reason,
    reversed_at,
    reversed_by_user_id
  )
  values (
    p_reversal_id,
    v_tenant_id,
    p_payment_id,
    p_cash_session_id,
    v_reason,
    coalesce(p_reversed_at, pg_catalog.now()),
    v_actor_id
  )
  on conflict (id) do nothing;

  update public.payments as payment
  set status = 'reversed'
  where payment.id = p_payment_id
    and payment.tenant_id = v_tenant_id;

  return p_reversal_id;
end;
$$;

create function public.reverse_payment(
  p_reversal_id uuid,
  p_payment_id uuid,
  p_cash_session_id uuid,
  p_reason text,
  p_reversed_at timestamp with time zone
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.reverse_payment(
    p_reversal_id,
    p_payment_id,
    p_cash_session_id,
    p_reason,
    p_reversed_at
  );
$$;

revoke all on function security.confirm_payment(uuid, text, timestamp with time zone) from public, anon, authenticated;
revoke all on function public.confirm_payment(uuid, text, timestamp with time zone) from public, anon, authenticated;
revoke all on function security.reverse_payment(uuid, uuid, uuid, text, timestamp with time zone) from public, anon, authenticated;
revoke all on function public.reverse_payment(uuid, uuid, uuid, text, timestamp with time zone) from public, anon, authenticated;

grant execute on function security.confirm_payment(uuid, text, timestamp with time zone) to authenticated;
grant execute on function public.confirm_payment(uuid, text, timestamp with time zone) to authenticated;
grant execute on function security.reverse_payment(uuid, uuid, uuid, text, timestamp with time zone) to authenticated;
grant execute on function public.reverse_payment(uuid, uuid, uuid, text, timestamp with time zone) to authenticated;

-- ============================================================
-- 2 y 3. El arqueo, corregido
-- ============================================================
CREATE OR REPLACE FUNCTION security.close_cash_session(p_cash_session_id uuid, p_counted_cash_gs bigint, p_closed_at timestamp with time zone, p_closing_note text)
 RETURNS TABLE(closing_expected_gs bigint, closing_counted_gs bigint, closing_difference_gs bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    -- Tambien los revertidos: el reverso se resta aparte por su propio turno, y
    -- si se excluyeran de aca un reverso del MISMO turno se restaria dos veces.
    and payment.status in ('confirmed', 'reversed');

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
    and movement.movement_type in ('cash_in', 'correction_in');

  select coalesce(pg_catalog.sum(movement.amount_gs), 0)
    into v_cash_out_gs
  from public.cash_movements as movement
  where movement.cash_session_id = p_cash_session_id
    and movement.tenant_id = v_tenant_id
    and movement.movement_type in ('cash_out', 'vault_drop', 'supplier_payout', 'correction_out');

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
$function$;
