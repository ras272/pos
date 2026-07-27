-- Fundación multi-tenant de Task 5. Las membresías vigentes son la única
-- autoridad de tenant; no se usan metadata ni roles del JWT para autorizar.

create schema security;

-- El creador de las migraciones es postgres. Estas reglas cierran los
-- privilegios implícitos para los objetos de aplicación actuales y futuros.
alter default privileges for role postgres revoke create on schemas from public;
alter default privileges for role postgres revoke all on tables from public;
alter default privileges for role postgres revoke all on sequences from public;
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres revoke usage on types from public;
alter default privileges for role postgres in schema public, security revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public, security revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public, security revoke execute on functions from anon, authenticated;
alter default privileges for role postgres in schema public, security revoke usage on types from anon, authenticated;

revoke all on schema public from public, anon;
revoke all on schema security from public, anon, authenticated;
revoke create on schema public from authenticated;

grant usage on schema public to authenticated;
grant usage on schema security to authenticated;

create type public.tenant_role as enum ('owner', 'admin', 'member');

create table public.tenants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  name text not null,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint tenants_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint tenants_name_length_check check (pg_catalog.char_length(name) <= 120),
  constraint tenants_status_check check (status in ('active', 'suspended'))
);

create table public.tenant_memberships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  role public.tenant_role not null,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint tenant_memberships_status_check check (status in ('active', 'suspended')),
  constraint tenant_memberships_tenant_id_user_id_key unique (tenant_id, user_id)
);

create table public.establishments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  name text not null,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint establishments_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint establishments_name_length_check check (pg_catalog.char_length(name) <= 120),
  constraint establishments_status_check check (status in ('active', 'suspended')),
  constraint establishments_tenant_id_name_key unique (tenant_id, name)
);

create table security.tenant_bootstrap_audit (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  actor_id uuid not null references auth.users (id) on delete restrict,
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null references public.establishments (id) on delete restrict,
  created_at timestamp with time zone not null default pg_catalog.now()
);

-- Las claves únicas compuestas indexan tenant_id como prefijo. user_id necesita
-- un índice independiente porque no es el primer campo de esa clave compuesta.
create index tenant_memberships_user_id_idx on public.tenant_memberships (user_id);
create index tenant_bootstrap_audit_actor_id_created_at_idx on security.tenant_bootstrap_audit (actor_id, created_at);
create index tenant_bootstrap_audit_tenant_id_idx on security.tenant_bootstrap_audit (tenant_id);
create index tenant_bootstrap_audit_establishment_id_idx on security.tenant_bootstrap_audit (establishment_id);

create function security.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function security.prevent_tenant_id_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.tenant_id is distinct from old.tenant_id then
    raise exception 'tenant_id is immutable';
  end if;

  return new;
end;
$$;

create function security.prevent_bootstrap_audit_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'tenant bootstrap audit is append-only';
end;
$$;

create trigger tenants_updated_at
before update on public.tenants
for each row
execute function security.set_updated_at();

create trigger tenant_memberships_updated_at
before update on public.tenant_memberships
for each row
execute function security.set_updated_at();

create trigger establishments_updated_at
before update on public.establishments
for each row
execute function security.set_updated_at();

create trigger tenant_memberships_tenant_id_immutable
before update on public.tenant_memberships
for each row
execute function security.prevent_tenant_id_change();

create trigger establishments_tenant_id_immutable
before update on public.establishments
for each row
execute function security.prevent_tenant_id_change();

create trigger tenant_bootstrap_audit_append_only
before update or delete on security.tenant_bootstrap_audit
for each row
execute function security.prevent_bootstrap_audit_mutation();

create function security.is_tenant_member(
  p_tenant_id uuid,
  p_roles public.tenant_role[] default null
)
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
        and tenant.status = 'active'
        and (p_roles is null or membership.role = any (p_roles))
    );
$$;

create function security.bootstrap_tenant(
  p_tenant_name text,
  p_establishment_name text
)
returns table (tenant_id uuid, establishment_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_establishment_id uuid;
  v_tenant_name text;
  v_establishment_name text;
begin
  if v_actor_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated user is required';
  end if;

  v_tenant_name := pg_catalog.btrim(p_tenant_name);
  v_establishment_name := pg_catalog.btrim(p_establishment_name);

  if v_tenant_name is null or v_tenant_name = '' then
    raise exception using
      errcode = '22023',
      message = 'tenant name must not be blank';
  end if;

  if pg_catalog.char_length(v_tenant_name) > 120 then
    raise exception using
      errcode = '22023',
      message = 'tenant name must be between 1 and 120 characters';
  end if;

  if v_establishment_name is null or v_establishment_name = '' then
    raise exception using
      errcode = '22023',
      message = 'establishment name must not be blank';
  end if;

  if pg_catalog.char_length(v_establishment_name) > 120 then
    raise exception using
      errcode = '22023',
      message = 'establishment name must be between 1 and 120 characters';
  end if;

  -- Foundation anti-burst control: one actor can commit at most three
  -- successful tenant bootstraps in any rolling one-hour window. A transaction
  -- advisory lock serializes the count and audit insert for the same actor;
  -- rejected validation never reaches this point and therefore never consumes quota.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor_id::text, 0)
  );

  if (
    select pg_catalog.count(*)
    from security.tenant_bootstrap_audit as audit
    where audit.actor_id = v_actor_id
      and audit.created_at >= pg_catalog.now() - interval '1 hour'
  ) >= 3 then
    raise exception using
      errcode = 'P0001',
      message = 'tenant bootstrap rate limit exceeded';
  end if;

  insert into public.tenants (name)
  values (v_tenant_name)
  returning id into v_tenant_id;

  insert into public.tenant_memberships (tenant_id, user_id, role)
  values (v_tenant_id, v_actor_id, 'owner');

  insert into public.establishments (tenant_id, name)
  values (v_tenant_id, v_establishment_name)
  returning id into v_establishment_id;

  insert into security.tenant_bootstrap_audit (
    actor_id,
    tenant_id,
    establishment_id
  )
  values (v_actor_id, v_tenant_id, v_establishment_id);

  return query select v_tenant_id, v_establishment_id;
end;
$$;

-- El wrapper sigue siendo invoker. authenticated recibe el mínimo grant sobre
-- el helper para permitir la delegación; security queda fuera del allowlist del
-- Data API (`api.schemas = ["public"]`), por lo que no es una superficie RPC.
create function public.bootstrap_tenant(
  p_tenant_name text,
  p_establishment_name text
)
returns table (tenant_id uuid, establishment_id uuid)
language sql
security invoker
set search_path = ''
as $$
  select *
  from security.bootstrap_tenant(p_tenant_name, p_establishment_name);
$$;

alter table public.tenants enable row level security;
alter table public.tenants force row level security;
alter table public.tenant_memberships enable row level security;
alter table public.tenant_memberships force row level security;
alter table public.establishments enable row level security;
alter table public.establishments force row level security;
alter table security.tenant_bootstrap_audit enable row level security;
alter table security.tenant_bootstrap_audit force row level security;

create policy tenants_select_active_members
on public.tenants
for select
to authenticated
using ((select security.is_tenant_member(id)));

create policy tenants_update_active_admins
on public.tenants
for update
to authenticated
using (
  (
    select security.is_tenant_member(
      id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
)
with check (
  (
    select security.is_tenant_member(
      id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

create policy establishments_select_active_members
on public.establishments
for select
to authenticated
using (status = 'active' and (select security.is_tenant_member(tenant_id)));

create policy establishments_insert_active_admins
on public.establishments
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

create policy establishments_update_active_admins
on public.establishments
for update
to authenticated
using (
  status = 'active'
  and (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
)
with check (
  status = 'active'
  and (
    select security.is_tenant_member(
      tenant_id,
      array['owner', 'admin']::public.tenant_role[]
    )
  )
);

revoke all on all tables in schema public, security from public, anon, authenticated;
revoke all on all sequences in schema public, security from public, anon, authenticated;
revoke all on type public.tenant_role from public, anon, authenticated;
revoke all on all functions in schema public, security from public, anon, authenticated;

grant usage on type public.tenant_role to authenticated;
grant select, update on table public.tenants to authenticated;
grant select, insert, update on table public.establishments to authenticated;
grant execute on function security.is_tenant_member(uuid, public.tenant_role[]) to authenticated;
grant execute on function security.bootstrap_tenant(text, text) to authenticated;
grant execute on function public.bootstrap_tenant(text, text) to authenticated;
