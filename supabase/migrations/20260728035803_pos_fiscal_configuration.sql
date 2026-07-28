-- Configuracion fiscal: puntos de expedicion, timbrados, umbral innominado,
-- certificados F1, contadores de numeracion y clientes.
--
-- Le da a la capa de comprobantes fuentes que no pueden mentir: el codigo de
-- punto de expedicion, el del establecimiento, el numero y la vigencia del
-- timbrado y el rango autorizado quedan inmutables despues del alta, y el
-- umbral se resuelve por la fecha de la venta y no por la de hoy.
--
-- Cada rango de numeracion es una FILA, no una columna del contador: renovar
-- es insertar, y un documento firmado sin conexion bajo el rango anterior
-- reconcilia contra la fila que lo contiene en vez de reventar contra el nuevo.

alter table public.establishments
  add column establishment_code text,
  add constraint establishments_establishment_code_check
    check (establishment_code is null or establishment_code ~ '^[0-9]{3}$');

create table public.pos_terminals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  name text not null,
  -- El código del punto de expedición. Formato provisional: sale de la
  -- convención SIFEN conocida, no de la spec del proveedor de facturación.
  expedition_point_code text not null,
  -- Prefijo del número de COMANDA, no del número fiscal: es lo que evita que
  -- dos tablets offline colisionen en orders.code.
  order_code_prefix text not null,
  device_label text,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint pos_terminals_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint pos_terminals_name_length_check check (pg_catalog.char_length(name) <= 60),
  constraint pos_terminals_expedition_point_code_check check (expedition_point_code ~ '^[0-9]{3}$'),
  constraint pos_terminals_order_code_prefix_not_blank check (pg_catalog.btrim(order_code_prefix) <> ''),
  constraint pos_terminals_order_code_prefix_length_check check (pg_catalog.char_length(order_code_prefix) <= 3),
  constraint pos_terminals_device_label_length_check check (device_label is null or pg_catalog.char_length(device_label) <= 120),
  constraint pos_terminals_status_check check (status in ('active', 'archived')),
  constraint pos_terminals_id_establishment_id_key unique (id, establishment_id),
  -- Unique COMPLETA y no parcial `where status = 'active'`: dos filas para el
  -- mismo punto de expedición (una archivada, una nueva) partirían el
  -- correlativo en dos y dejarían el hueco que la DNIT no perdona.
  constraint pos_terminals_establishment_id_expedition_point_code_key unique (establishment_id, expedition_point_code),
  constraint pos_terminals_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict
);

create table public.fiscal_timbrados (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  -- Alcance de CONTRIBUYENTE, no de local.
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  number text not null,
  valid_from date not null,
  -- Nullable: el timbrado electrónico puede ser indefinido. Terminarlo antes de
  -- tiempo es status = 'revoked', no un cambio de fecha.
  valid_to date,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint fiscal_timbrados_number_check check (number ~ '^[0-9]{8}$'),
  constraint fiscal_timbrados_validity_check check (valid_to is null or valid_to >= valid_from),
  constraint fiscal_timbrados_status_check check (status in ('active', 'expired', 'revoked')),
  constraint fiscal_timbrados_id_tenant_id_key unique (id, tenant_id),
  -- Unique COMPLETA: un número de timbrado no se reutiliza jamás, ni tras vencer.
  constraint fiscal_timbrados_tenant_id_number_key unique (tenant_id, number)
);

create table public.fiscal_thresholds (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  -- El 7.000.000 vive acá, en ninguna constante de código ni en ningún check.
  anonymous_buyer_threshold_gs public.guaranies not null,
  effective_from date not null,
  effective_to date,
  -- El decreto que lo fijó, para poder auditar por qué una venta vieja no
  -- capturó cédula.
  source_note text,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint fiscal_thresholds_anonymous_buyer_threshold_gs_check check (anonymous_buyer_threshold_gs > 0),
  constraint fiscal_thresholds_period_check check (effective_to is null or effective_to > effective_from),
  constraint fiscal_thresholds_source_note_length_check check (source_note is null or pg_catalog.char_length(source_note) <= 300),
  constraint fiscal_thresholds_status_check check (status in ('active', 'superseded')),
  -- Bicondicional: 'vigente' y 'sin fecha de cierre' son la misma cosa dicha dos
  -- veces. Sin esto, una fila superseded con effective_to null deja al local sin
  -- umbral resoluble y ocupa el índice de la única vigencia abierta.
  constraint fiscal_thresholds_status_period_check check ((status = 'active') = (effective_to is null)),
  constraint fiscal_thresholds_tenant_id_effective_from_key unique (tenant_id, effective_from)
);

create table public.fiscal_certificates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  -- Nullable: un tenant puede tener un solo certificado para todos sus locales.
  establishment_id uuid,
  issuer text not null,
  serial_number text not null,
  subject_ruc text not null,
  not_before date not null,
  expires_at date not null,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  -- NO existen ni pueden agregarse columnas certificate, p12, pfx,
  -- private_key, password, passphrase ni secret. Un assert de catálogo en
  -- 004 falla si alguien las agrega en una migración futura.
  constraint fiscal_certificates_issuer_not_blank check (pg_catalog.btrim(issuer) <> ''),
  constraint fiscal_certificates_issuer_length_check check (pg_catalog.char_length(issuer) <= 200),
  constraint fiscal_certificates_serial_number_not_blank check (pg_catalog.btrim(serial_number) <> ''),
  constraint fiscal_certificates_serial_number_length_check check (pg_catalog.char_length(serial_number) <= 120),
  constraint fiscal_certificates_subject_ruc_not_blank check (pg_catalog.btrim(subject_ruc) <> ''),
  constraint fiscal_certificates_subject_ruc_length_check check (pg_catalog.char_length(subject_ruc) <= 20),
  constraint fiscal_certificates_period_check check (expires_at > not_before),
  constraint fiscal_certificates_status_check check (status in ('active', 'expired', 'revoked')),
  -- Ancla: la capa de comprobantes cuelga signing_certificate_id de acá para
  -- poder responder 'qué documentos firmé con el certificado vencido'.
  constraint fiscal_certificates_id_tenant_id_key unique (id, tenant_id),
  constraint fiscal_certificates_tenant_id_serial_number_key unique (tenant_id, serial_number),
  constraint fiscal_certificates_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict
);

create table public.document_counters (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  pos_terminal_id uuid not null,
  timbrado_id uuid not null,
  document_type text not null,
  -- Un rango = una fila. Renovar es INSERTAR, nunca reescribir: si el rango
  -- vigente y el last_number vivieran en la misma fila, renovar dejaría fuera de
  -- rango a todo documento ya firmado, impreso y entregado bajo el rango
  -- anterior, y la ventana de 72 h vuelve ese caso el NORMAL, no el raro.
  range_from bigint not null,
  range_to bigint not null,
  last_number bigint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint document_counters_document_type_check check (document_type in ('invoice', 'credit_note')),
  constraint document_counters_range_from_check check (range_from >= 1),
  constraint document_counters_range_to_check check (range_to >= range_from and range_to <= 9999999),
  -- UN SOLO check sobre last_number. Dos checks sobre la misma columna se
  -- llamarían los dos document_counters_last_number_check bajo la convención de
  -- nombres y el create table no compilaría (42710). El `>= 0` es redundante:
  -- range_from ya es >= 1.
  constraint document_counters_last_number_check check (last_number = 0 or (last_number >= range_from and last_number <= range_to)),
  constraint document_counters_status_check check (status in ('active', 'exhausted', 'closed')),
  -- Nombre acortado a propósito y con criterio explícito: el canónico
  -- document_counters_pos_terminal_id_document_type_timbrado_id_range_from_key
  -- mide 74 caracteres y Postgres lo truncaría en silencio a 63, rompiendo todo
  -- assert de pgTAP por nombre.
  constraint document_counters_terminal_type_timbrado_range_from_key unique (pos_terminal_id, document_type, timbrado_id, range_from),
  constraint document_counters_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  constraint document_counters_pos_terminal_id_fkey foreign key (pos_terminal_id, establishment_id)
    references public.pos_terminals (id, establishment_id) on delete restrict,
  constraint document_counters_timbrado_id_fkey foreign key (timbrado_id, tenant_id)
    references public.fiscal_timbrados (id, tenant_id) on delete restrict
);

create table public.customers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  -- 'RUC' y 'CI' son la única excepción a identificadores en inglés: son
  -- acrónimos paraguayos sin equivalente.
  doc_type text not null,
  doc_number text not null,
  -- Dígito verificador SEPARADO, nunca concatenado al número.
  ruc_dv smallint,
  name text not null,
  email text,
  phone text,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint customers_doc_type_check check (doc_type in ('RUC', 'CI')),
  constraint customers_doc_number_not_blank check (pg_catalog.btrim(doc_number) <> ''),
  constraint customers_doc_number_length_check check (pg_catalog.char_length(doc_number) <= 20),
  constraint customers_doc_number_format_check check (doc_number ~ '^[0-9A-Za-z]{1,20}$'),
  constraint customers_ruc_dv_check check ((doc_type = 'CI' and ruc_dv is null) or (doc_type = 'RUC' and ruc_dv between 0 and 9)),
  constraint customers_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint customers_name_length_check check (pg_catalog.char_length(name) <= 120),
  constraint customers_email_length_check check (email is null or pg_catalog.char_length(email) <= 160),
  constraint customers_phone_length_check check (phone is null or pg_catalog.char_length(phone) <= 40),
  constraint customers_status_check check (status in ('active', 'archived')),
  constraint customers_id_tenant_id_key unique (id, tenant_id),
  -- Unique COMPLETA y no parcial where status = 'active': archivar y recrear el
  -- mismo RUC partiría la identidad del comprador en dos filas.
  constraint customers_tenant_id_doc_type_doc_number_key unique (tenant_id, doc_type, doc_number)
);

create function security.prevent_establishment_code_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.establishment_code is not null
     and new.establishment_code is distinct from old.establishment_code then
    raise exception 'establishment code is immutable';
  end if;

  return new;
end;
$$;

create function security.prevent_expedition_point_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.expedition_point_code is distinct from old.expedition_point_code then
    raise exception 'expedition point code is immutable';
  end if;

  if new.establishment_id is distinct from old.establishment_id then
    raise exception 'expedition point establishment is immutable';
  end if;

  return new;
end;
$$;

create function security.prevent_timbrado_identity_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.number is distinct from old.number then
    raise exception 'fiscal stamp number is immutable';
  end if;

  if new.valid_from is distinct from old.valid_from
     or new.valid_to is distinct from old.valid_to then
    raise exception 'fiscal stamp validity is immutable';
  end if;

  if old.status in ('expired', 'revoked') and new.status = 'active' then
    raise exception 'fiscal stamp cannot return to active';
  end if;

  return new;
end;
$$;

create function security.prevent_fiscal_threshold_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.anonymous_buyer_threshold_gs is distinct from old.anonymous_buyer_threshold_gs
     or new.effective_from is distinct from old.effective_from then
    raise exception 'fiscal threshold amount and start date are immutable';
  end if;

  if old.effective_to is not null
     and new.effective_to is distinct from old.effective_to then
    raise exception 'a closed fiscal threshold period cannot be reopened';
  end if;

  return new;
end;
$$;

create function security.prevent_counter_range_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.pos_terminal_id is distinct from old.pos_terminal_id
     or new.document_type is distinct from old.document_type
     or new.timbrado_id is distinct from old.timbrado_id
     or new.range_from is distinct from old.range_from
     or new.range_to is distinct from old.range_to then
    raise exception 'authorized number range is immutable';
  end if;

  if new.last_number < old.last_number then
    raise exception 'document counter cannot go backwards';
  end if;

  if old.status <> 'active' and new.status = 'active' then
    raise exception 'a closed number range cannot be reopened';
  end if;

  return new;
end;
$$;

create function security.assign_number_range(
  p_pos_terminal_id uuid,
  p_timbrado_id uuid,
  p_document_type text,
  p_range_from bigint,
  p_range_to bigint
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
  v_terminal_status text;
  v_timbrado_status text;
  v_timbrado_valid_to date;
  v_counter_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  -- El tenant se DERIVA de una fila leída del servidor, nunca de un parámetro:
  -- este cuerpo corre como postgres, que tiene BYPASSRLS, así que la membresía
  -- es el único control que queda en pie.
  select terminal.tenant_id, terminal.establishment_id, terminal.status
    into v_tenant_id, v_establishment_id, v_terminal_status
  from public.pos_terminals as terminal
  where terminal.id = p_pos_terminal_id;

  if v_tenant_id is null
     or not security.is_tenant_member(
       v_tenant_id,
       array['owner', 'admin']::public.tenant_role[]
     ) then
    raise exception using
      errcode = '42501',
      message = 'not authorized to assign a number range';
  end if;

  if v_terminal_status <> 'active' then
    raise exception using
      errcode = 'P0001',
      message = 'pos terminal is not active';
  end if;

  if p_document_type is null
     or p_document_type not in ('invoice', 'credit_note') then
    raise exception using
      errcode = '22023',
      message = 'document type must be invoice or credit_note';
  end if;

  if p_range_from is null
     or p_range_to is null
     or p_range_from < 1
     or p_range_to < p_range_from
     or p_range_to > 9999999 then
    raise exception using
      errcode = '22023',
      message = 'number range must be within 1 and 9999999';
  end if;

  select stamp.status, stamp.valid_to
    into v_timbrado_status, v_timbrado_valid_to
  from public.fiscal_timbrados as stamp
  where stamp.id = p_timbrado_id
    and stamp.tenant_id = v_tenant_id;

  if v_timbrado_status is null then
    raise exception using
      errcode = '22023',
      message = 'fiscal stamp is not available for this terminal';
  end if;

  if v_timbrado_status <> 'active' then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal stamp is not active';
  end if;

  if v_timbrado_valid_to is not null
     and v_timbrado_valid_to < pg_catalog.now()::date then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal stamp has expired';
  end if;

  -- Serializa la renovación del mismo punto de expedición: dos admins que
  -- renuevan a la vez no pueden dejar dos rangos vigentes ni dos solapados.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_pos_terminal_id::text || ':' || p_document_type, 0)
  );

  -- El solapamiento es lo único que puede volver ambigua la reconciliación
  -- 'la fila que CONTIENE el número'. No va como exclusion constraint porque
  -- exigiría btree_gist, sin precedente en el repo.
  if exists (
    select 1
    from public.document_counters as counter
    where counter.pos_terminal_id = p_pos_terminal_id
      and counter.document_type = p_document_type
      and counter.timbrado_id = p_timbrado_id
      and p_range_from <= counter.range_to
      and p_range_to >= counter.range_from
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'number range overlaps an existing range';
  end if;

  -- El rango anterior se CIERRA conservando su last_number. No se resetea nada:
  -- un documento firmado bajo ese rango puede llegar hasta 72 h después.
  update public.document_counters as counter
  set status = case
    when counter.last_number >= counter.range_to then 'exhausted'
    else 'closed'
  end
  where counter.pos_terminal_id = p_pos_terminal_id
    and counter.document_type = p_document_type
    and counter.status = 'active';

  insert into public.document_counters (
    tenant_id,
    establishment_id,
    pos_terminal_id,
    timbrado_id,
    document_type,
    range_from,
    range_to
  )
  values (
    v_tenant_id,
    v_establishment_id,
    p_pos_terminal_id,
    p_timbrado_id,
    p_document_type,
    p_range_from,
    p_range_to
  )
  returning id into v_counter_id;

  return v_counter_id;
end;
$$;

create function public.assign_number_range(
  p_pos_terminal_id uuid,
  p_timbrado_id uuid,
  p_document_type text,
  p_range_from bigint,
  p_range_to bigint
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.assign_number_range(
    p_pos_terminal_id,
    p_timbrado_id,
    p_document_type,
    p_range_from,
    p_range_to
  );
$$;

create function security.set_fiscal_threshold(
  p_establishment_id uuid,
  p_amount_gs bigint,
  p_effective_from date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_last_from date;
  v_threshold_id uuid;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  -- El umbral es del contribuyente, pero el tenant se deriva igual de una fila
  -- del servidor: el establecimiento es la única identidad que aporta el
  -- cliente y su tenant_id no se lee de ningún payload.
  select establishment.tenant_id
    into v_tenant_id
  from public.establishments as establishment
  where establishment.id = p_establishment_id;

  if v_tenant_id is null
     or not security.is_tenant_member(
       v_tenant_id,
       array['owner', 'admin']::public.tenant_role[]
     ) then
    raise exception using
      errcode = '42501',
      message = 'not authorized to set the fiscal threshold';
  end if;

  if p_amount_gs is null or p_amount_gs <= 0 then
    raise exception using
      errcode = '22023',
      message = 'fiscal threshold amount must be positive';
  end if;

  if p_effective_from is null then
    raise exception using
      errcode = '22023',
      message = 'fiscal threshold start date is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_tenant_id::text, 0)
  );

  -- Vigencias estrictamente hacia adelante: sin esto, corregir un dato
  -- histórico deja dos períodos solapados y 'qué umbral aplicaba el 15/06'
  -- pasa a tener dos respuestas.
  select pg_catalog.max(threshold.effective_from)
    into v_last_from
  from public.fiscal_thresholds as threshold
  where threshold.tenant_id = v_tenant_id;

  if v_last_from is not null and p_effective_from <= v_last_from then
    raise exception using
      errcode = '22023',
      message = 'fiscal threshold periods must move forward';
  end if;

  update public.fiscal_thresholds as threshold
  set effective_to = p_effective_from,
      status = 'superseded'
  where threshold.tenant_id = v_tenant_id
    and threshold.effective_to is null;

  insert into public.fiscal_thresholds (
    tenant_id,
    anonymous_buyer_threshold_gs,
    effective_from
  )
  values (v_tenant_id, p_amount_gs, p_effective_from)
  returning id into v_threshold_id;

  return v_threshold_id;
end;
$$;

create function public.set_fiscal_threshold(
  p_establishment_id uuid,
  p_amount_gs bigint,
  p_effective_from date
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select security.set_fiscal_threshold(
    p_establishment_id,
    p_amount_gs,
    p_effective_from
  );
$$;

revoke all on function
  security.prevent_establishment_code_change(),
  security.prevent_expedition_point_change(),
  security.prevent_timbrado_identity_change(),
  security.prevent_fiscal_threshold_change(),
  security.prevent_counter_range_change(),
  security.assign_number_range(uuid, uuid, text, bigint, bigint),
  security.set_fiscal_threshold(uuid, bigint, date),
  public.assign_number_range(uuid, uuid, text, bigint, bigint),
  public.set_fiscal_threshold(uuid, bigint, date)
from public, anon, authenticated;

grant execute on function security.assign_number_range(uuid, uuid, text, bigint, bigint) to authenticated;
grant execute on function security.set_fiscal_threshold(uuid, bigint, date) to authenticated;
grant execute on function public.assign_number_range(uuid, uuid, text, bigint, bigint) to authenticated;
grant execute on function public.set_fiscal_threshold(uuid, bigint, date) to authenticated;

create unique index establishments_tenant_id_code_uidx on public.establishments (tenant_id, establishment_code) where establishment_code is not null;
create index pos_terminals_tenant_id_updated_at_idx on public.pos_terminals (tenant_id, updated_at);
create index pos_terminals_establishment_id_tenant_id_idx on public.pos_terminals (establishment_id, tenant_id);
create unique index pos_terminals_active_order_prefix_uidx on public.pos_terminals (establishment_id, order_code_prefix) where status = 'active';
create index fiscal_timbrados_tenant_id_updated_at_idx on public.fiscal_timbrados (tenant_id, updated_at);
create index fiscal_timbrados_tenant_id_valid_to_idx on public.fiscal_timbrados (tenant_id, valid_to);
create index fiscal_thresholds_tenant_id_updated_at_idx on public.fiscal_thresholds (tenant_id, updated_at);
create unique index fiscal_thresholds_open_period_uidx on public.fiscal_thresholds (tenant_id) where effective_to is null;
create index fiscal_certificates_tenant_id_updated_at_idx on public.fiscal_certificates (tenant_id, updated_at);
create index fiscal_certificates_establishment_id_tenant_id_idx on public.fiscal_certificates (establishment_id, tenant_id);
create index fiscal_certificates_tenant_id_expires_at_idx on public.fiscal_certificates (tenant_id, expires_at);
create index document_counters_tenant_id_updated_at_idx on public.document_counters (tenant_id, updated_at);
create index document_counters_establishment_id_tenant_id_idx on public.document_counters (establishment_id, tenant_id);
create index document_counters_pos_terminal_id_establishment_id_idx on public.document_counters (pos_terminal_id, establishment_id);
create index document_counters_timbrado_id_tenant_id_idx on public.document_counters (timbrado_id, tenant_id);
create unique index document_counters_active_range_uidx on public.document_counters (pos_terminal_id, document_type) where status = 'active';
create index customers_tenant_id_updated_at_idx on public.customers (tenant_id, updated_at);
create index customers_tenant_id_name_idx on public.customers (tenant_id, name);

create trigger establishments_establishment_code_immutable
before update on public.establishments
for each row
execute function security.prevent_establishment_code_change();

create trigger pos_terminals_expedition_point_immutable
before update on public.pos_terminals
for each row
execute function security.prevent_expedition_point_change();

create trigger pos_terminals_tenant_id_immutable
before update on public.pos_terminals
for each row
execute function security.prevent_tenant_id_change();

create trigger pos_terminals_updated_at
before update on public.pos_terminals
for each row
execute function security.set_updated_at();

create trigger fiscal_timbrados_identity_immutable
before update on public.fiscal_timbrados
for each row
execute function security.prevent_timbrado_identity_change();

create trigger fiscal_timbrados_tenant_id_immutable
before update on public.fiscal_timbrados
for each row
execute function security.prevent_tenant_id_change();

create trigger fiscal_timbrados_updated_at
before update on public.fiscal_timbrados
for each row
execute function security.set_updated_at();

create trigger fiscal_thresholds_period_immutable
before update on public.fiscal_thresholds
for each row
execute function security.prevent_fiscal_threshold_change();

create trigger fiscal_thresholds_tenant_id_immutable
before update on public.fiscal_thresholds
for each row
execute function security.prevent_tenant_id_change();

create trigger fiscal_thresholds_updated_at
before update on public.fiscal_thresholds
for each row
execute function security.set_updated_at();

create trigger fiscal_certificates_tenant_id_immutable
before update on public.fiscal_certificates
for each row
execute function security.prevent_tenant_id_change();

create trigger fiscal_certificates_updated_at
before update on public.fiscal_certificates
for each row
execute function security.set_updated_at();

create trigger document_counters_range_immutable
before update on public.document_counters
for each row
execute function security.prevent_counter_range_change();

create trigger document_counters_tenant_id_immutable
before update on public.document_counters
for each row
execute function security.prevent_tenant_id_change();

create trigger document_counters_updated_at
before update on public.document_counters
for each row
execute function security.set_updated_at();

create trigger customers_tenant_id_immutable
before update on public.customers
for each row
execute function security.prevent_tenant_id_change();

create trigger customers_updated_at
before update on public.customers
for each row
execute function security.set_updated_at();

-- RLS: la spec no la traia. El assert de catalogo de 002 la habria exigido igual.
alter table public.pos_terminals enable row level security;
alter table public.pos_terminals force row level security;
alter table public.fiscal_timbrados enable row level security;
alter table public.fiscal_timbrados force row level security;
alter table public.fiscal_thresholds enable row level security;
alter table public.fiscal_thresholds force row level security;
alter table public.fiscal_certificates enable row level security;
alter table public.fiscal_certificates force row level security;
alter table public.document_counters enable row level security;
alter table public.document_counters force row level security;
alter table public.customers enable row level security;
alter table public.customers force row level security;

create policy pos_terminals_select_active_members
on public.pos_terminals
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy pos_terminals_insert_active_admins
on public.pos_terminals
for insert
to authenticated
with check (
  status = 'active'
  and (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy pos_terminals_update_active_admins
on public.pos_terminals
for update
to authenticated
using (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
)
with check (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy fiscal_timbrados_select_active_members
on public.fiscal_timbrados
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy fiscal_timbrados_insert_active_admins
on public.fiscal_timbrados
for insert
to authenticated
with check (
  status = 'active'
  and (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy fiscal_timbrados_update_active_admins
on public.fiscal_timbrados
for update
to authenticated
using (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
)
with check (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy fiscal_thresholds_select_active_members
on public.fiscal_thresholds
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy fiscal_certificates_select_active_members
on public.fiscal_certificates
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy fiscal_certificates_insert_active_admins
on public.fiscal_certificates
for insert
to authenticated
with check (
  status = 'active'
  and (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy fiscal_certificates_update_active_admins
on public.fiscal_certificates
for update
to authenticated
using (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
)
with check (
  (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy document_counters_select_active_members
on public.document_counters
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy customers_select_active_members
on public.customers
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy customers_insert_active_members
on public.customers
for insert
to authenticated
with check (
  status = 'active'
  and (select security.is_tenant_member(tenant_id))
);

create policy customers_update_active_members
on public.customers
for update
to authenticated
using ((select security.is_tenant_member(tenant_id)))
with check ((select security.is_tenant_member(tenant_id)));

-- Los revoke se enumeran objeto por objeto: un revoke masivo le arrancaria a
-- authenticated los grants que la fundacion ya otorgo.
revoke all on table public.pos_terminals from public, anon, authenticated;
grant select, insert, update on table public.pos_terminals to authenticated;
revoke all on table public.fiscal_timbrados from public, anon, authenticated;
grant select, insert, update on table public.fiscal_timbrados to authenticated;
revoke all on table public.fiscal_thresholds from public, anon, authenticated;
grant select on table public.fiscal_thresholds to authenticated;
revoke all on table public.fiscal_certificates from public, anon, authenticated;
grant select, insert, update on table public.fiscal_certificates to authenticated;
revoke all on table public.document_counters from public, anon, authenticated;
grant select on table public.document_counters to authenticated;
revoke all on table public.customers from public, anon, authenticated;
grant select, insert, update on table public.customers to authenticated;

