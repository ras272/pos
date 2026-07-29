-- El guardian de turno abierto esta colgado de tres tablas: cash_movements,
-- payments y payment_reversals. Pero leia new.adjusts_cash_session_id, columna
-- que solo existe en cash_movements, asi que cualquier cobro reventaba con
-- 42703 "record new has no field". plpgsql resuelve los campos en tiempo de
-- ejecucion, por eso el trigger se creo sin protestar y el error habria
-- aparecido recien al cobrar la primera venta.
--
-- Se lee por jsonb, que devuelve null cuando la clave no existe, para que la
-- misma funcion sirva a las tres tablas sin suponer la forma de la fila.

create or replace function security.require_open_cash_session()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_adjusts_cash_session_id uuid;
begin
  if not exists (
    select 1
    from public.cash_sessions as session
    where session.id = new.cash_session_id
      and session.status = 'open'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'cash session is closed';
  end if;

  -- Solo cash_movements tiene la correccion de un turno anterior. En payments y
  -- payment_reversals la clave no existe y esto queda en null.
  v_adjusts_cash_session_id :=
    (pg_catalog.to_jsonb(new) ->> 'adjusts_cash_session_id')::uuid;

  if v_adjusts_cash_session_id is not null and not exists (
    select 1
    from public.cash_sessions as session
    where session.id = v_adjusts_cash_session_id
      and session.status = 'closed'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'adjusted cash session must be closed';
  end if;

  return new;
end;
$$;

revoke all on function security.require_open_cash_session() from public, anon, authenticated;
