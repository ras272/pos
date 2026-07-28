-- La cuenta abierta y el turno de caja.
--
-- Salon y mostrador comparten una sola tabla de pedido: lo unico que los
-- distingue es el canal y si hay mesa. Duplicar el modelo por canal habria
-- duplicado tambien el cierre y la numeracion, que es donde estan los errores
-- caros.

create table public.orders (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  -- El discriminador. Duplicar el modelo por canal duplicaría también la
  -- numeración y el congelamiento, que es donde están todos los errores caros.
  channel text not null,
  table_id uuid,
  -- Número de COMANDA: prefijo del terminal + contador local ('A-014'). Admite
  -- huecos y no coordina con el servidor. NO es numeración fiscal.
  code text not null,
  -- Jornada operativa, la pone el dispositivo: un bar que cierra a las 3 am
  -- sigue en el día anterior.
  business_date date not null,
  guest_count smallint,
  note text,
  opened_by_user_id uuid not null references auth.users (id) on delete restrict,
  opened_at timestamp with time zone not null,
  closed_by_user_id uuid references auth.users (id) on delete restrict,
  closed_at timestamp with time zone,
  cancel_reason text,
  status text not null default 'open',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint orders_code_not_blank check (pg_catalog.btrim(code) <> ''),
  constraint orders_code_length_check check (pg_catalog.char_length(code) <= 12),
  constraint orders_note_length_check check (note is null or pg_catalog.char_length(note) <= 300),
  constraint orders_cancel_reason_length_check check (cancel_reason is null or pg_catalog.char_length(cancel_reason) <= 280),
  constraint orders_channel_check check (channel in ('dine_in', 'counter')),
  -- Bicondicional: mata de un saque 'salón sin mesa' y 'mostrador con mesa'.
  constraint orders_channel_table_check check ((channel = 'dine_in') = (table_id is not null)),
  constraint orders_guest_count_check check (guest_count is null or guest_count between 1 and 99),
  constraint orders_guest_count_channel_check check (channel = 'dine_in' or guest_count is null),
  constraint orders_status_check check (status in ('open', 'settled', 'cancelled')),
  -- Bicondicional en los DOS sentidos: ni 'open' con datos de cierre, ni un
  -- estado terminal sin ellos.
  constraint orders_closure_check check (
    (status = 'open' and closed_at is null and closed_by_user_id is null)
    or (status in ('settled', 'cancelled') and closed_at is not null and closed_by_user_id is not null)
  ),
  constraint orders_cancel_reason_check check ((status = 'cancelled') = (cancel_reason is not null)),
  constraint orders_closure_order_check check (closed_at is null or closed_at >= opened_at),
  constraint orders_id_tenant_id_key unique (id, tenant_id),
  -- Ancla de local: la capa fiscal engancha documents por (order_id,
  -- establishment_id) para que una cuenta de Villa Morra no pueda emitirse con
  -- el código de establecimiento de San Lorenzo.
  constraint orders_id_establishment_id_key unique (id, establishment_id),
  constraint orders_establishment_id_business_date_code_key unique (establishment_id, business_date, code),
  constraint orders_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  -- MATCH SIMPLE: con table_id null la FK no se evalúa, que es exactamente lo
  -- que necesita el mostrador.
  constraint orders_table_id_fkey foreign key (table_id, establishment_id)
    references public.dining_tables (id, establishment_id) on delete restrict
);

create table public.order_lines (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  order_id uuid not null,
  product_id uuid not null,
  line_number integer not null,
  -- Snapshot ya en la línea mutable: renombrar el producto a mitad del servicio
  -- no puede cambiar la comanda que ya se imprimió.
  product_name text not null,
  -- La ÚNICA columna con decimales del esquema: media porción, venta por peso.
  quantity numeric(12, 3) not null,
  -- CON IVA incluido y congelado al agregar: si suben el precio a mitad del
  -- servicio, la mesa abierta no cambia.
  unit_price_gs public.guaranies not null,
  iva_rate smallint not null,
  -- bigint pelado: la suma de los deltas de los modificadores puede ser negativa.
  modifiers_total_gs bigint not null default 0,
  -- Magnitud positiva que se resta, nunca un monto negativo colado en un total.
  discount_gs public.guaranies not null default 0,
  -- Ya redondeado al guaraní: el redondeo se resuelve al ESCRIBIR, nunca al
  -- leer, o dos dispositivos imprimen totales distintos del mismo ticket.
  line_total_gs public.guaranies not null,
  -- Ganchos que no cuestan tablas: dividir la cuenta por comensal, ordenar por
  -- tiempo del servicio y saber si la comanda ya salió a cocina.
  seat_number smallint,
  course smallint,
  kitchen_note text,
  sent_to_kitchen_at timestamp with time zone,
  voided_at timestamp with time zone,
  voided_by_user_id uuid references auth.users (id) on delete restrict,
  void_reason text,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint order_lines_product_name_not_blank check (pg_catalog.btrim(product_name) <> ''),
  constraint order_lines_product_name_length_check check (pg_catalog.char_length(product_name) <= 120),
  constraint order_lines_kitchen_note_length_check check (kitchen_note is null or pg_catalog.char_length(kitchen_note) <= 140),
  constraint order_lines_void_reason_length_check check (void_reason is null or pg_catalog.char_length(void_reason) <= 140),
  constraint order_lines_line_number_check check (line_number > 0),
  constraint order_lines_quantity_check check (quantity > 0),
  constraint order_lines_iva_rate_check check (iva_rate in (5, 10)),
  constraint order_lines_seat_number_check check (seat_number is null or seat_number > 0),
  constraint order_lines_course_check check (course is null or course between 1 and 9),
  -- El dominio guaranies ya obliga line_total_gs >= 0, así que esta igualdad
  -- implica sola que el descuento nunca supera el bruto de la línea. Un total de
  -- cero es legal: es la cortesía por un plato mal salido.
  constraint order_lines_composition_check check (
    line_total_gs = pg_catalog.round(quantity * (unit_price_gs + modifiers_total_gs))::bigint - discount_gs
  ),
  constraint order_lines_status_check check (status in ('active', 'voided')),
  -- Quién sacó el plato es el control antifraude más pedido en un POS de
  -- restaurante; el bicondicional impide media anulación en cualquier sentido.
  constraint order_lines_void_check check (
    (status = 'voided') = (voided_at is not null and voided_by_user_id is not null and void_reason is not null)
  ),
  constraint order_lines_id_tenant_id_key unique (id, tenant_id),
  constraint order_lines_order_id_line_number_key unique (order_id, line_number),
  constraint order_lines_order_id_fkey foreign key (order_id, tenant_id)
    references public.orders (id, tenant_id) on delete restrict,
  constraint order_lines_product_id_fkey foreign key (product_id, tenant_id)
    references public.products (id, tenant_id) on delete restrict
);

create table public.order_line_modifiers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  order_line_id uuid not null,
  modifier_option_id uuid not null,
  modifier_group_name text not null,
  name text not null,
  -- Snapshot; bigint pelado porque un delta puede ser negativo.
  price_delta_gs bigint not null,
  -- Identidad dentro de la línea, no presentación. 'Doble queso' son dos filas
  -- de la misma opción: si la unicidad fuera por display_order, congelar esas
  -- dos filas en el comprobante reventaría con el cliente en la caja.
  sequence_number smallint not null,
  display_order smallint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint order_line_modifiers_modifier_group_name_not_blank check (pg_catalog.btrim(modifier_group_name) <> ''),
  constraint order_line_modifiers_modifier_group_name_length_check check (pg_catalog.char_length(modifier_group_name) <= 80),
  constraint order_line_modifiers_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint order_line_modifiers_name_length_check check (pg_catalog.char_length(name) <= 80),
  constraint order_line_modifiers_sequence_number_check check (sequence_number > 0),
  constraint order_line_modifiers_display_order_check check (display_order >= 0),
  constraint order_line_modifiers_status_check check (status in ('active', 'voided')),
  constraint order_line_modifiers_id_tenant_id_key unique (id, tenant_id),
  constraint order_line_modifiers_order_line_id_sequence_number_key unique (order_line_id, sequence_number),
  constraint order_line_modifiers_order_line_id_fkey foreign key (order_line_id, tenant_id)
    references public.order_lines (id, tenant_id) on delete restrict,
  constraint order_line_modifiers_modifier_option_id_fkey foreign key (modifier_option_id, tenant_id)
    references public.modifier_options (id, tenant_id) on delete restrict
);

create table public.cash_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  -- Una caja es un punto de expedición: el turno cuelga del terminal, no del
  -- local. Anclado solo por tenant, el arqueo de dos cajas del mismo local se
  -- mezcla y las dos quedan mintiendo el mismo día.
  pos_terminal_id uuid not null,
  business_date date not null,
  opened_by_user_id uuid not null references auth.users (id) on delete restrict,
  opened_at timestamp with time zone not null,
  opening_float_gs public.guaranies not null default 0,
  closed_by_user_id uuid references auth.users (id) on delete restrict,
  closed_at timestamp with time zone,
  -- Lo que se CONTÓ en el cajón.
  counted_cash_gs public.guaranies,
  -- Lo que DEBÍA haber. Lo calcula y congela el RPC de cierre, nunca el cliente:
  -- si el cajero pudiera escribirlo, el arqueo sería una declaración jurada de
  -- sí mismo.
  expected_cash_gs public.guaranies,
  -- Columna generada legal: la resta de bigint es IMMUTABLE y ninguno de los dos
  -- operandos es a su vez generado. Faltante negativo, sobrante positivo.
  cash_difference_gs bigint generated always as (counted_cash_gs - expected_cash_gs) stored,
  closing_note text,
  status text not null default 'open',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint cash_sessions_closing_note_length_check check (closing_note is null or pg_catalog.char_length(closing_note) <= 280),
  constraint cash_sessions_status_check check (status in ('open', 'closed')),
  -- Bicondicional completo: no se cierra un turno sin arqueo ni queda un turno
  -- abierto con cifras de cierre cargadas.
  constraint cash_sessions_closure_check check (
    (status = 'open' and closed_at is null and closed_by_user_id is null and counted_cash_gs is null and expected_cash_gs is null)
    or (status = 'closed' and closed_at is not null and closed_by_user_id is not null and counted_cash_gs is not null and expected_cash_gs is not null)
  ),
  constraint cash_sessions_closure_order_check check (closed_at is null or closed_at >= opened_at),
  constraint cash_sessions_id_tenant_id_key unique (id, tenant_id),
  -- Ancla de terminal: la capa fiscal engancha documents y payments por
  -- (cash_session_id, pos_terminal_id) para que el Z de una caja no reclame la
  -- plata que está en el cajón de la otra.
  constraint cash_sessions_id_pos_terminal_id_key unique (id, pos_terminal_id),
  constraint cash_sessions_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  constraint cash_sessions_pos_terminal_id_fkey foreign key (pos_terminal_id, establishment_id)
    references public.pos_terminals (id, establishment_id) on delete restrict
);

create table public.cash_movements (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  -- El turno VIGENTE donde se registra. El establecimiento y el terminal se
  -- derivan de él: no se duplican y por lo tanto no pueden contradecirlo.
  cash_session_id uuid not null,
  -- El turno YA CERRADO que esta fila corrige. Corregir un arqueo cerrado es un
  -- movimiento del turno vigente, nunca una escritura sobre el turno cerrado.
  adjusts_cash_session_id uuid,
  -- El SIGNO lo da el tipo, nunca un monto negativo colado en la suma.
  movement_type text not null,
  amount_gs public.guaranies not null,
  reason text not null,
  occurred_at timestamp with time zone not null,
  created_by_user_id uuid not null references auth.users (id) on delete restrict,
  -- Un solo valor: existe para cumplir la convención y para que sumar un estado
  -- futuro sea explícito, no para admitir anulación.
  status text not null default 'confirmed',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint cash_movements_reason_not_blank check (pg_catalog.btrim(reason) <> ''),
  constraint cash_movements_reason_length_check check (pg_catalog.char_length(reason) <= 200),
  constraint cash_movements_amount_gs_check check (amount_gs > 0),
  constraint cash_movements_movement_type_check check (
    movement_type in ('cash_in', 'cash_out', 'vault_drop', 'supplier_payout', 'correction')
  ),
  constraint cash_movements_correction_check check ((movement_type = 'correction') = (adjusts_cash_session_id is not null)),
  constraint cash_movements_self_adjust_check check (adjusts_cash_session_id is distinct from cash_session_id),
  constraint cash_movements_status_check check (status in ('confirmed')),
  constraint cash_movements_cash_session_id_fkey foreign key (cash_session_id, tenant_id)
    references public.cash_sessions (id, tenant_id) on delete restrict,
  -- MATCH SIMPLE: con adjusts_cash_session_id null la FK no se evalúa.
  constraint cash_movements_adjusts_cash_session_id_fkey foreign key (adjusts_cash_session_id, tenant_id)
    references public.cash_sessions (id, tenant_id) on delete restrict
);

create function security.require_tenant_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := pg_catalog.to_jsonb(new);
  v_column text;
  v_actor_id uuid;
begin
  foreach v_column in array tg_argv loop
    v_actor_id := (v_row ->> v_column)::uuid;

    if v_actor_id is not null and not exists (
      select 1
      from public.tenant_memberships as membership
      join public.tenants as tenant on tenant.id = membership.tenant_id
      where membership.tenant_id = new.tenant_id
        and membership.user_id = v_actor_id
        and membership.status = 'active'
        and tenant.status = 'active'
    ) then
      raise exception using
        errcode = '42501',
        message = 'actor is not an active member of the tenant';
    end if;
  end loop;

  return new;
end;
$$;

create function security.enforce_order_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.closed_at is not null then
    if pg_catalog.to_jsonb(new) - 'updated_at' is not distinct from pg_catalog.to_jsonb(old) - 'updated_at' then
      return new;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'closed order is immutable';
  end if;

  if new.status <> 'open' and new.closed_by_user_id is distinct from auth.uid() then
    raise exception using
      errcode = '42501',
      message = 'order must be closed by the acting user';
  end if;

  return new;
end;
$$;

create function security.enforce_order_line_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.status = 'voided' then
      if pg_catalog.to_jsonb(new) - 'updated_at' is not distinct from pg_catalog.to_jsonb(old) - 'updated_at' then
        return new;
      end if;

      raise exception using
        errcode = 'P0001',
        message = 'voided order line is immutable';
    end if;

    if new.status = 'voided' and new.voided_by_user_id is distinct from auth.uid() then
      raise exception using
        errcode = '42501',
        message = 'order line must be voided by the acting user';
    end if;
  end if;

  if not exists (
    select 1
    from public.orders as parent_order
    where parent_order.id = new.order_id
      and parent_order.closed_at is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'closed order cannot change its lines';
  end if;

  return new;
end;
$$;

create function security.enforce_order_line_modifier_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.order_lines as line
    join public.orders as parent_order on parent_order.id = line.order_id
    where line.id = new.order_line_id
      and line.status = 'active'
      and parent_order.closed_at is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'order line is not open for modifiers';
  end if;

  return new;
end;
$$;

create function security.enforce_cash_session_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status = 'closed' then
    if pg_catalog.to_jsonb(new) - 'updated_at' is not distinct from pg_catalog.to_jsonb(old) - 'updated_at' then
      return new;
    end if;

    raise exception using
      errcode = 'P0001',
      message = 'closed cash session is immutable';
  end if;

  if new.status = 'closed' and new.closed_by_user_id is distinct from auth.uid() then
    raise exception using
      errcode = '42501',
      message = 'cash session must be closed by the acting user';
  end if;

  return new;
end;
$$;

create function security.require_open_cash_session()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
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

  if new.adjusts_cash_session_id is not null and not exists (
    select 1
    from public.cash_sessions as session
    where session.id = new.adjusts_cash_session_id
      and session.status = 'closed'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'adjusted cash session must be closed';
  end if;

  return new;
end;
$$;

create function security.prevent_cash_movement_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'cash movement is append-only';
end;
$$;

create index orders_tenant_id_updated_at_idx on public.orders (tenant_id, updated_at);
create index orders_establishment_id_tenant_id_idx on public.orders (establishment_id, tenant_id);
create index orders_table_id_establishment_id_idx on public.orders (table_id, establishment_id);
create index orders_opened_by_user_id_opened_at_idx on public.orders (opened_by_user_id, opened_at);
create index orders_closed_by_user_id_idx on public.orders (closed_by_user_id);
create unique index orders_open_table_uidx on public.orders (table_id) where status = 'open' and table_id is not null;
create index orders_open_by_establishment_idx on public.orders (establishment_id, opened_at) where status = 'open';
create index order_lines_tenant_id_updated_at_idx on public.order_lines (tenant_id, updated_at);
create index order_lines_order_id_tenant_id_idx on public.order_lines (order_id, tenant_id);
create index order_lines_product_id_tenant_id_idx on public.order_lines (product_id, tenant_id);
create index order_lines_voided_by_user_id_idx on public.order_lines (voided_by_user_id);
create index order_lines_pending_kitchen_idx on public.order_lines (order_id, course, created_at) where status = 'active' and sent_to_kitchen_at is null;
create index order_line_modifiers_tenant_id_updated_at_idx on public.order_line_modifiers (tenant_id, updated_at);
create index order_line_modifiers_order_line_id_tenant_id_idx on public.order_line_modifiers (order_line_id, tenant_id);
create index order_line_modifiers_modifier_option_id_tenant_id_idx on public.order_line_modifiers (modifier_option_id, tenant_id);
create index cash_sessions_tenant_id_updated_at_idx on public.cash_sessions (tenant_id, updated_at);
create index cash_sessions_establishment_id_tenant_id_idx on public.cash_sessions (establishment_id, tenant_id);
create index cash_sessions_pos_terminal_id_establishment_id_idx on public.cash_sessions (pos_terminal_id, establishment_id);
create index cash_sessions_opened_by_user_id_opened_at_idx on public.cash_sessions (opened_by_user_id, opened_at);
create index cash_sessions_closed_by_user_id_idx on public.cash_sessions (closed_by_user_id);
create unique index cash_sessions_open_terminal_uidx on public.cash_sessions (pos_terminal_id) where status = 'open';
create index cash_sessions_establishment_business_date_idx on public.cash_sessions (establishment_id, business_date);
-- El cursor del sync es created_at y no updated_at: en una tabla append-only
-- updated_at no se mueve nunca. El prefijo [tenant_id] cubre igual la FK.
create index cash_movements_tenant_id_created_at_idx on public.cash_movements (tenant_id, created_at);
create index cash_movements_cash_session_id_tenant_id_idx on public.cash_movements (cash_session_id, tenant_id);
create index cash_movements_adjusts_cash_session_id_tenant_id_idx on public.cash_movements (adjusts_cash_session_id, tenant_id);
create index cash_movements_created_by_user_id_idx on public.cash_movements (created_by_user_id);

create trigger orders_actor_guard
before insert or update on public.orders
for each row
execute function security.require_tenant_actor('opened_by_user_id', 'closed_by_user_id');

create trigger orders_closure_guard
before update on public.orders
for each row
execute function security.enforce_order_lifecycle();

create trigger orders_tenant_id_immutable
before update on public.orders
for each row
execute function security.prevent_tenant_id_change();

create trigger orders_updated_at
before update on public.orders
for each row
execute function security.set_updated_at();

create trigger order_lines_actor_guard
before insert or update on public.order_lines
for each row
execute function security.require_tenant_actor('voided_by_user_id');

create trigger order_lines_lifecycle_guard
before insert or update on public.order_lines
for each row
execute function security.enforce_order_line_lifecycle();

create trigger order_lines_tenant_id_immutable
before update on public.order_lines
for each row
execute function security.prevent_tenant_id_change();

create trigger order_lines_updated_at
before update on public.order_lines
for each row
execute function security.set_updated_at();

create trigger order_line_modifiers_lifecycle_guard
before insert or update on public.order_line_modifiers
for each row
execute function security.enforce_order_line_modifier_scope();

create trigger order_line_modifiers_tenant_id_immutable
before update on public.order_line_modifiers
for each row
execute function security.prevent_tenant_id_change();

create trigger order_line_modifiers_updated_at
before update on public.order_line_modifiers
for each row
execute function security.set_updated_at();

create trigger cash_sessions_actor_guard
before insert or update on public.cash_sessions
for each row
execute function security.require_tenant_actor('opened_by_user_id', 'closed_by_user_id');

create trigger cash_sessions_closure_guard
before update on public.cash_sessions
for each row
execute function security.enforce_cash_session_lifecycle();

create trigger cash_sessions_tenant_id_immutable
before update on public.cash_sessions
for each row
execute function security.prevent_tenant_id_change();

create trigger cash_sessions_updated_at
before update on public.cash_sessions
for each row
execute function security.set_updated_at();

create trigger cash_movements_actor_guard
before insert on public.cash_movements
for each row
execute function security.require_tenant_actor('created_by_user_id');

create trigger cash_movements_append_only
before update or delete on public.cash_movements
for each row
execute function security.prevent_cash_movement_mutation();

create trigger cash_movements_session_guard
before insert on public.cash_movements
for each row
execute function security.require_open_cash_session();

-- Los dos triggers que siguen no llegan a ejecutarse nunca: _append_only los
-- precede alfabéticamente en el mismo timing y aborta antes. Existen porque las
-- aserciones de catálogo de 002 exigen prevent_tenant_id_change en toda tabla
-- pública con tenant_id y set_updated_at en toda tabla con updated_at.
create trigger cash_movements_tenant_id_immutable
before update on public.cash_movements
for each row
execute function security.prevent_tenant_id_change();

create trigger cash_movements_updated_at
before update on public.cash_movements
for each row
execute function security.set_updated_at();

-- RLS: la spec no la traia; el assert de catalogo de 002 la exige igual.
alter table public.orders enable row level security;
alter table public.orders force row level security;
alter table public.order_lines enable row level security;
alter table public.order_lines force row level security;
alter table public.order_line_modifiers enable row level security;
alter table public.order_line_modifiers force row level security;
alter table public.cash_sessions enable row level security;
alter table public.cash_sessions force row level security;
alter table public.cash_movements enable row level security;
alter table public.cash_movements force row level security;

create policy orders_select_active_members
on public.orders
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy orders_insert_active_members
on public.orders
for insert
to authenticated
with check (
  status = 'open'
  and closed_at is null
  and closed_by_user_id is null
  and cancel_reason is null
  and opened_by_user_id = (select auth.uid())
  and (select security.is_tenant_member(tenant_id))
);

create policy orders_update_active_members
on public.orders
for update
to authenticated
using ((select security.is_tenant_member(tenant_id)))
with check ((select security.is_tenant_member(tenant_id)));

create policy order_lines_select_active_members
on public.order_lines
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy order_lines_insert_active_members
on public.order_lines
for insert
to authenticated
with check (
  status = 'active'
  and voided_at is null
  and voided_by_user_id is null
  and void_reason is null
  and (select security.is_tenant_member(tenant_id))
);

create policy order_lines_update_active_members
on public.order_lines
for update
to authenticated
using ((select security.is_tenant_member(tenant_id)))
with check ((select security.is_tenant_member(tenant_id)));

create policy order_line_modifiers_select_active_members
on public.order_line_modifiers
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy order_line_modifiers_insert_active_members
on public.order_line_modifiers
for insert
to authenticated
with check (
  status = 'active'
  and (select security.is_tenant_member(tenant_id))
);

create policy order_line_modifiers_update_active_members
on public.order_line_modifiers
for update
to authenticated
using ((select security.is_tenant_member(tenant_id)))
with check ((select security.is_tenant_member(tenant_id)));

create policy cash_sessions_select_active_members
on public.cash_sessions
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy cash_sessions_insert_active_members
on public.cash_sessions
for insert
to authenticated
with check (
  status = 'open'
  and closed_at is null
  and closed_by_user_id is null
  and counted_cash_gs is null
  and expected_cash_gs is null
  and closing_note is null
  and opened_by_user_id = (select auth.uid())
  and (select security.is_tenant_member(tenant_id))
);

create policy cash_movements_select_active_members
on public.cash_movements
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

-- Una sola policy con predicado dependiente del rol: sacar plata del cajón
-- (vault_drop, supplier_payout) y corregir un turno cerrado es exactamente lo
-- que hay que exigirle a owner o admin; un ingreso o egreso menor lo hace el
-- cajero. Sin policy de UPDATE: la tabla es append-only.
create policy cash_movements_insert_active_members
on public.cash_movements
for insert
to authenticated
with check (
  status = 'confirmed'
  and created_by_user_id = (select auth.uid())
  and (
    (
      movement_type in ('cash_in', 'cash_out')
      and (select security.is_tenant_member(tenant_id))
    )
    or (
      select security.is_tenant_member(
        tenant_id,
        array['owner', 'admin']::public.tenant_role[]
      )
    )
  )
);

revoke all on table
  public.orders,
  public.order_lines,
  public.order_line_modifiers,
  public.cash_sessions,
  public.cash_movements
from public, anon, authenticated;
revoke all on function
  security.require_tenant_actor(),
  security.enforce_order_lifecycle(),
  security.enforce_order_line_lifecycle(),
  security.enforce_order_line_modifier_scope(),
  security.enforce_cash_session_lifecycle(),
  security.require_open_cash_session(),
  security.prevent_cash_movement_mutation()
from public, anon, authenticated;
-- Cerrar la cuenta NO es un PATCH. authenticated no recibe UPDATE de tabla:
-- solo las tres columnas que un mozo mueve con la mesa abierta. status,
-- closed_at, closed_by_user_id y cancel_reason quedan fuera de PostgREST y solo
-- las escribe un RPC definer, que es dueño de la tabla y no ve el grant.
grant select, insert on table public.orders to authenticated;
grant update (table_id, guest_count, note) on table public.orders to authenticated;
-- El snapshot no se toca después del insert: product_id, product_name,
-- unit_price_gs, iva_rate y line_number quedan fuera del grant de columna. Sacar
-- un plato SÍ es acto del mozo, así que status y las tres columnas de anulación
-- entran.
grant select, insert on table public.order_lines to authenticated;
grant update (
  quantity,
  modifiers_total_gs,
  discount_gs,
  line_total_gs,
  seat_number,
  course,
  kitchen_note,
  sent_to_kitchen_at,
  status,
  voided_at,
  voided_by_user_id,
  void_reason
) on table public.order_lines to authenticated;
-- El snapshot (nombre del grupo, nombre, delta y sequence_number) no se edita:
-- quitar un agregado es status = 'voided', que es lo único mutable junto con la
-- presentación.
grant select, insert on table public.order_line_modifiers to authenticated;
grant update (display_order, status) on table public.order_line_modifiers to authenticated;
-- Abrir el turno es acto del cajero y el índice parcial impide el segundo turno
-- abierto por caja. Cerrarlo NO: sin grant de UPDATE, expected_cash_gs solo lo
-- puede escribir el RPC de cierre, que lo calcula del lado del servidor.
grant select, insert on table public.cash_sessions to authenticated;
grant select, insert on table public.cash_movements to authenticated;
