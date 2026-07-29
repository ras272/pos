-- El congelado del cobro no puede comparar una columna generada.
--
-- `payments.charged_total_gs` es GENERATED ALWAYS sobre amount_gs + tip_gs, y
-- Postgres la calcula DESPUES de los triggers BEFORE. Dentro del trigger, `new`
-- la ve nula mientras `old` trae el valor guardado, asi que la comparacion por
-- jsonb detectaba una diferencia que no existe y cualquier update legitimo
-- moria con "payment is frozen".
--
-- Eso rompia el unico camino que enlaza un cobro con su comprobante:
-- issue_document setea payments.document_id despues de emitir, porque el cobro
-- ocurre antes de que exista el numero. Con el congelado mal comparado, emitir
-- era imposible.
--
-- Excluirla de la comparacion es seguro por construccion: es GENERATED ALWAYS,
-- ningun cliente puede escribirla, y Postgres la recalcula desde amount_gs y
-- tip_gs, que siguen congeladas. `cash_sessions.cash_difference_gs` es la otra
-- generada del esquema y su tabla no usa esta comparacion, asi que no aplica.

create or replace function security.prevent_payment_mutation()
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
    'updated_at',
    -- Generada: en un BEFORE trigger todavia no esta calculada.
    'charged_total_gs'
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
