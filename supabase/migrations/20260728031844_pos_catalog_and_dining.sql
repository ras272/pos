-- Catálogo y salón: la primera capa del dominio del POS.
--
-- Cubre qué se vende (categorías, productos, agregados y variantes) y dónde se
-- sirve (sectores y mesas). No cubre pedidos, cobros ni comprobantes: eso viene
-- en migraciones siguientes, cada una capaz de reconstruir desde cero por su
-- cuenta.
--
-- Dos reglas que atraviesan todo el archivo:
--
-- 1. Cada FK a una tabla del dominio se ancla por tenant (o por establecimiento)
--    con DOS columnas. La validación de una foreign key corre con privilegios
--    elevados y NO consulta RLS: sin el ancla, un cliente que conozca el uuid de
--    una categoría ajena puede referenciarla desde su propio tenant.
-- 2. Cada FK lleva índice COMPLETO, nunca parcial. Un índice parcial satisface el
--    scan estructural de pgTAP (que no mira indpred) pero no sirve al ON DELETE
--    ni al join. Los parciales existen solo como índices adicionales.

-- Guaraníes: enteros y no negativos. No hay decimales en la moneda y no existe
-- ninguna columna de precio sin IVA en todo el esquema; el precio se guarda con
-- IVA incluido y se desagrega dividiendo, nunca al revés.
create domain public.guaranies as bigint check (value >= 0);

-- Ancla de tenant sobre la tabla de la fundación, para que las FK compuestas del
-- dominio puedan referenciarla.
alter table public.establishments
  add constraint establishments_id_tenant_id_key unique (id, tenant_id);

create table public.product_categories (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  name text not null,
  display_order smallint not null default 0,
  color text,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint product_categories_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint product_categories_name_length_check check (pg_catalog.char_length(name) <= 80),
  constraint product_categories_display_order_check check (display_order >= 0),
  constraint product_categories_color_check check (color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  constraint product_categories_status_check check (status in ('active', 'archived')),
  constraint product_categories_id_tenant_id_key unique (id, tenant_id)
);

create table public.products (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  category_id uuid not null,
  name text not null,
  short_name text,
  code text,
  price_gs public.guaranies not null,
  -- Entero de porcentaje, nunca el divisor 1,1 ni un float. 10% servicios,
  -- 5% ciertos bienes de canasta. El IVA es por ítem, jamás por negocio.
  iva_rate smallint not null default 10,
  -- Agotado del día. NO es stock: no hay cantidad, no se descuenta y no genera
  -- ningún movimiento.
  is_available boolean not null default true,
  display_order smallint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint products_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint products_name_length_check check (pg_catalog.char_length(name) <= 120),
  constraint products_short_name_length_check check (short_name is null or pg_catalog.char_length(short_name) <= 24),
  constraint products_code_length_check check (code is null or pg_catalog.char_length(code) <= 40),
  constraint products_iva_rate_check check (iva_rate in (5, 10)),
  constraint products_display_order_check check (display_order >= 0),
  constraint products_status_check check (status in ('active', 'archived')),
  constraint products_id_tenant_id_key unique (id, tenant_id),
  constraint products_category_id_fkey foreign key (category_id, tenant_id)
    references public.product_categories (id, tenant_id) on delete restrict
);

create table public.modifier_groups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  name text not null,
  -- La obligatoriedad se DERIVA de selection_min: no hay booleano redundante que
  -- pueda contradecirla. Una variante ("tamaño") es un grupo con min = max = 1;
  -- un agregado ("extras") es el mismo mecanismo con min = 0.
  selection_min smallint not null default 0,
  selection_max smallint not null default 1,
  display_order smallint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint modifier_groups_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint modifier_groups_name_length_check check (pg_catalog.char_length(name) <= 80),
  constraint modifier_groups_selection_min_check check (selection_min >= 0),
  constraint modifier_groups_selection_max_check check (selection_max >= 1),
  constraint modifier_groups_selection_range_check check (selection_max >= selection_min),
  constraint modifier_groups_display_order_check check (display_order >= 0),
  constraint modifier_groups_status_check check (status in ('active', 'archived')),
  constraint modifier_groups_id_tenant_id_key unique (id, tenant_id)
);

create table public.modifier_options (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  modifier_group_id uuid not null,
  name text not null,
  -- bigint pelado y no public.guaranies: un delta puede ser negativo
  -- ("porción chica" -5.000).
  price_delta_gs bigint not null default 0,
  display_order smallint not null default 0,
  is_default boolean not null default false,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint modifier_options_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint modifier_options_name_length_check check (pg_catalog.char_length(name) <= 80),
  constraint modifier_options_display_order_check check (display_order >= 0),
  constraint modifier_options_status_check check (status in ('active', 'archived')),
  constraint modifier_options_id_tenant_id_key unique (id, tenant_id),
  constraint modifier_options_group_id_fkey foreign key (modifier_group_id, tenant_id)
    references public.modifier_groups (id, tenant_id) on delete restrict
);

create table public.product_modifier_groups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  product_id uuid not null,
  modifier_group_id uuid not null,
  -- El mismo grupo puede ser obligatorio en el lomito y opcional en la
  -- hamburguesa, así que la obligatoriedad se decide en el puente.
  is_required boolean not null default false,
  display_order smallint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint product_modifier_groups_display_order_check check (display_order >= 0),
  constraint product_modifier_groups_status_check check (status in ('active', 'archived')),
  constraint product_modifier_groups_product_id_fkey foreign key (product_id, tenant_id)
    references public.products (id, tenant_id) on delete restrict,
  constraint product_modifier_groups_group_id_fkey foreign key (modifier_group_id, tenant_id)
    references public.modifier_groups (id, tenant_id) on delete restrict
);

create table public.dining_areas (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  name text not null,
  display_order smallint not null default 0,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint dining_areas_name_not_blank check (pg_catalog.btrim(name) <> ''),
  constraint dining_areas_name_length_check check (pg_catalog.char_length(name) <= 60),
  constraint dining_areas_display_order_check check (display_order >= 0),
  constraint dining_areas_status_check check (status in ('active', 'archived')),
  constraint dining_areas_id_establishment_id_key unique (id, establishment_id),
  constraint dining_areas_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict
);

create table public.dining_tables (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  establishment_id uuid not null,
  dining_area_id uuid not null,
  -- El número que dice el mozo: '12', 'T3'.
  code text not null,
  seats smallint,
  position_x smallint,
  position_y smallint,
  status text not null default 'active',
  created_at timestamp with time zone not null default pg_catalog.now(),
  updated_at timestamp with time zone not null default pg_catalog.now(),
  constraint dining_tables_code_not_blank check (pg_catalog.btrim(code) <> ''),
  constraint dining_tables_code_length_check check (pg_catalog.char_length(code) <= 12),
  constraint dining_tables_seats_check check (seats is null or seats between 1 and 40),
  constraint dining_tables_status_check check (status in ('active', 'archived')),
  constraint dining_tables_id_establishment_id_key unique (id, establishment_id),
  constraint dining_tables_establishment_id_fkey foreign key (establishment_id, tenant_id)
    references public.establishments (id, tenant_id) on delete restrict,
  -- Dos columnas y no tres: el tenant ya quedó anclado por la FK de
  -- establecimiento, así que una mesa de un sector de otro local es imposible.
  constraint dining_tables_area_id_fkey foreign key (dining_area_id, establishment_id)
    references public.dining_areas (id, establishment_id) on delete restrict
);

-- Índices completos de cada foreign key. El primero de cada tabla cubre además
-- el pull incremental por tenant.
create index product_categories_tenant_id_updated_at_idx on public.product_categories (tenant_id, updated_at);

create index products_tenant_id_updated_at_idx on public.products (tenant_id, updated_at);
create index products_category_id_tenant_id_idx on public.products (category_id, tenant_id);

create index modifier_groups_tenant_id_updated_at_idx on public.modifier_groups (tenant_id, updated_at);

create index modifier_options_tenant_id_updated_at_idx on public.modifier_options (tenant_id, updated_at);
create index modifier_options_group_id_tenant_id_idx on public.modifier_options (modifier_group_id, tenant_id);

create index product_modifier_groups_tenant_updated_idx on public.product_modifier_groups (tenant_id, updated_at);
create index product_modifier_groups_product_id_idx on public.product_modifier_groups (product_id, tenant_id);
create index product_modifier_groups_group_id_idx on public.product_modifier_groups (modifier_group_id, tenant_id);

create index dining_areas_tenant_id_updated_at_idx on public.dining_areas (tenant_id, updated_at);
create index dining_areas_establishment_id_idx on public.dining_areas (establishment_id, tenant_id);

create index dining_tables_tenant_id_updated_at_idx on public.dining_tables (tenant_id, updated_at);
create index dining_tables_establishment_id_idx on public.dining_tables (establishment_id, tenant_id);
create index dining_tables_area_id_establishment_idx on public.dining_tables (dining_area_id, establishment_id);

-- Unicidad solo entre filas vigentes: archivar libera el nombre, y restaurar
-- falla si mientras tanto alguien lo reusó.
create unique index product_categories_active_name_uidx on public.product_categories (tenant_id, name) where status = 'active';
create unique index products_active_name_uidx on public.products (tenant_id, name) where status = 'active';
create unique index products_active_code_uidx on public.products (tenant_id, code) where code is not null and status = 'active';
create unique index modifier_groups_active_name_uidx on public.modifier_groups (tenant_id, name) where status = 'active';
create unique index modifier_options_active_name_uidx on public.modifier_options (tenant_id, modifier_group_id, name) where status = 'active';
create unique index product_modifier_groups_active_uidx on public.product_modifier_groups (tenant_id, product_id, modifier_group_id) where status = 'active';
create unique index dining_areas_active_name_uidx on public.dining_areas (establishment_id, name) where status = 'active';
create unique index dining_tables_active_code_uidx on public.dining_tables (establishment_id, code) where status = 'active';

create trigger product_categories_updated_at
before update on public.product_categories
for each row
execute function security.set_updated_at();

create trigger products_updated_at
before update on public.products
for each row
execute function security.set_updated_at();

create trigger modifier_groups_updated_at
before update on public.modifier_groups
for each row
execute function security.set_updated_at();

create trigger modifier_options_updated_at
before update on public.modifier_options
for each row
execute function security.set_updated_at();

create trigger product_modifier_groups_updated_at
before update on public.product_modifier_groups
for each row
execute function security.set_updated_at();

create trigger dining_areas_updated_at
before update on public.dining_areas
for each row
execute function security.set_updated_at();

create trigger dining_tables_updated_at
before update on public.dining_tables
for each row
execute function security.set_updated_at();

create trigger product_categories_tenant_id_immutable
before update on public.product_categories
for each row
execute function security.prevent_tenant_id_change();

create trigger products_tenant_id_immutable
before update on public.products
for each row
execute function security.prevent_tenant_id_change();

create trigger modifier_groups_tenant_id_immutable
before update on public.modifier_groups
for each row
execute function security.prevent_tenant_id_change();

create trigger modifier_options_tenant_id_immutable
before update on public.modifier_options
for each row
execute function security.prevent_tenant_id_change();

create trigger product_modifier_groups_tenant_immutable
before update on public.product_modifier_groups
for each row
execute function security.prevent_tenant_id_change();

create trigger dining_areas_tenant_id_immutable
before update on public.dining_areas
for each row
execute function security.prevent_tenant_id_change();

create trigger dining_tables_tenant_id_immutable
before update on public.dining_tables
for each row
execute function security.prevent_tenant_id_change();

alter table public.product_categories enable row level security;
alter table public.product_categories force row level security;
alter table public.products enable row level security;
alter table public.products force row level security;
alter table public.modifier_groups enable row level security;
alter table public.modifier_groups force row level security;
alter table public.modifier_options enable row level security;
alter table public.modifier_options force row level security;
alter table public.product_modifier_groups enable row level security;
alter table public.product_modifier_groups force row level security;
alter table public.dining_areas enable row level security;
alter table public.dining_areas force row level security;
alter table public.dining_tables enable row level security;
alter table public.dining_tables force row level security;

-- SELECT sin filtro de status: una fila archivada tiene que poder leerse para
-- restaurarse y para reimprimir un comprobante viejo. El INSERT, en cambio, fija
-- el estado inicial: sin eso una fila podría nacer archivada y quedar
-- irrecuperable, porque no hay grant de DELETE en ninguna tabla del dominio.

create policy product_categories_select_active_members
on public.product_categories
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy product_categories_insert_active_admins
on public.product_categories
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

create policy product_categories_update_active_admins
on public.product_categories
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

create policy products_select_active_members
on public.products
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy products_insert_active_admins
on public.products
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

create policy products_update_active_admins
on public.products
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

create policy modifier_groups_select_active_members
on public.modifier_groups
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy modifier_groups_insert_active_admins
on public.modifier_groups
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

create policy modifier_groups_update_active_admins
on public.modifier_groups
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

create policy modifier_options_select_active_members
on public.modifier_options
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy modifier_options_insert_active_admins
on public.modifier_options
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

create policy modifier_options_update_active_admins
on public.modifier_options
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

create policy product_modifier_groups_select_members
on public.product_modifier_groups
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy product_modifier_groups_insert_admins
on public.product_modifier_groups
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

create policy product_modifier_groups_update_admins
on public.product_modifier_groups
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

create policy dining_areas_select_active_members
on public.dining_areas
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy dining_areas_insert_active_admins
on public.dining_areas
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

create policy dining_areas_update_active_admins
on public.dining_areas
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

create policy dining_tables_select_active_members
on public.dining_tables
for select
to authenticated
using ((select security.is_tenant_member(tenant_id)));

create policy dining_tables_insert_active_admins
on public.dining_tables
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

create policy dining_tables_update_active_admins
on public.dining_tables
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

-- Los revoke se enumeran objeto por objeto. Un `revoke all on all tables in
-- schema public` acá le arrancaría a authenticated los grants que la fundación
-- ya otorgó sobre tenants y establishments, y esta migración no los devuelve.
revoke all on table
  public.product_categories,
  public.products,
  public.modifier_groups,
  public.modifier_options,
  public.product_modifier_groups,
  public.dining_areas,
  public.dining_tables
from public, anon, authenticated;

revoke all on type public.guaranies from public, anon, authenticated;

-- Sin DELETE en ninguna: el dominio archiva con status, nunca borra físicamente.
grant select, insert, update on table
  public.product_categories,
  public.products,
  public.modifier_groups,
  public.modifier_options,
  public.product_modifier_groups,
  public.dining_areas,
  public.dining_tables
to authenticated;

grant usage on type public.guaranies to authenticated;
