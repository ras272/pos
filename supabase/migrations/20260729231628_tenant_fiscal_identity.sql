-- Identidad fiscal del emisor.
--
-- `security.issue_document` ya leia tenant.ruc, tenant.ruc_dv y
-- tenant.legal_name, pero las columnas no existian: plpgsql no valida el cuerpo
-- de una funcion al crearla, asi que la migracion anterior aplico igual y el
-- error habria aparecido recien al emitir la primera factura. Esto lo cierra.
--
-- Nullable porque la tabla ya tiene filas y una migracion forward-only no
-- agrega NOT NULL sin default. Mientras esten en null, issue_document rechaza
-- con "issuer fiscal identity is not configured", que es el comportamiento
-- correcto: sin RUC no se emite.

alter table public.tenants
  add column ruc text,
  add column ruc_dv smallint,
  add column legal_name text,
  add constraint tenants_ruc_check
    check (ruc is null or ruc ~ '^[0-9]{1,8}$'),
  add constraint tenants_ruc_dv_check
    check (ruc_dv is null or (ruc_dv >= 0 and ruc_dv <= 9)),
  add constraint tenants_legal_name_not_blank
    check (legal_name is null or pg_catalog.btrim(legal_name) <> ''),
  add constraint tenants_legal_name_length_check
    check (legal_name is null or pg_catalog.char_length(legal_name) <= 200),
  -- Los tres van juntos: media identidad fiscal no sirve para emitir y dejaria
  -- a issue_document fallando en la caja en vez de en la pantalla de alta.
  add constraint tenants_fiscal_identity_check
    check (
      (ruc is null and ruc_dv is null and legal_name is null)
      or (ruc is not null and ruc_dv is not null and legal_name is not null)
    );

-- Un RUC identifica a un contribuyente: no puede haber dos tenants con el mismo.
create unique index tenants_ruc_uidx on public.tenants (ruc) where ruc is not null;

create function security.validate_tenant_ruc_dv()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_weight integer := 2;
  v_sum integer := 0;
  v_index integer;
  v_expected smallint;
begin
  if new.ruc is null then
    return new;
  end if;

  -- El DV del RUC se calcula por modulo 11 sobre los digitos, de derecha a
  -- izquierda y con pesos de 2 en adelante. Se valida en el alta y no al
  -- emitir: un RUC mal tipeado tiene que doler en la pantalla de configuracion,
  -- no en la caja con el cliente esperando.
  for v_index in reverse pg_catalog.length(new.ruc)..1 loop
    v_sum := v_sum + (pg_catalog.substr(new.ruc, v_index, 1))::integer * v_weight;
    v_weight := v_weight + 1;
    if v_weight > 11 then
      v_weight := 2;
    end if;
  end loop;

  v_expected := case
    when v_sum % 11 <= 1 then 0
    else (11 - (v_sum % 11))::smallint
  end;

  if new.ruc_dv is distinct from v_expected then
    raise exception using
      errcode = 'P0001',
      message = 'issuer ruc check digit is invalid';
  end if;

  return new;
end;
$$;

-- El RUC del emisor es inmutable una vez cargado: cambiarlo reescribiria la
-- identidad fiscal de comprobantes ya entregados. La razon social si puede
-- cambiar, porque el comprobante congela su propia copia.
create function security.prevent_tenant_ruc_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.ruc is not null
     and (
       new.ruc is distinct from old.ruc
       or new.ruc_dv is distinct from old.ruc_dv
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'issuer ruc is immutable';
  end if;

  return new;
end;
$$;

create trigger tenants_ruc_dv_valid
before insert or update on public.tenants
for each row
execute function security.validate_tenant_ruc_dv();

create trigger tenants_ruc_immutable
before update on public.tenants
for each row
execute function security.prevent_tenant_ruc_change();

revoke all on function security.validate_tenant_ruc_dv() from public, anon, authenticated;
revoke all on function security.prevent_tenant_ruc_change() from public, anon, authenticated;
