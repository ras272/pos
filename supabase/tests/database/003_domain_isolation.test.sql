begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- Los fixtures entran como dueño de la base. Cada aserción de cliente cambia al
-- rol real de la API y provee únicamente un sub controlado.
insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'owner-b@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'member-a@example.test');

insert into public.tenants (id, name, status)
values
  ('10000000-0000-0000-0000-000000000001', 'Tenant A', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'Tenant B', 'active');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active');

insert into public.establishments (id, tenant_id, name, status)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local A', 'active'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Local B', 'active');

insert into public.product_categories (id, tenant_id, name)
values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Lomitos'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Cafetería');

insert into public.products (id, tenant_id, category_id, name, price_gs, iva_rate)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Lomito completo', 45000, 10),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Café con leche', 18000, 10);

insert into public.modifier_groups (id, tenant_id, name, selection_min, selection_max)
values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Extras', 0, 5),
  ('50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Tamaño', 1, 1);

insert into public.dining_areas (id, tenant_id, establishment_id, name)
values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Salón'),
  ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Terraza');

insert into public.dining_tables (id, tenant_id, establishment_id, dining_area_id, code)
values
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '12');

-- Aislamiento A -> B en lectura.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select results_eq(
  $$select id from public.product_categories order by id$$,
  array['30000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no ve las categorías de Tenant B'
);

select results_eq(
  $$select id from public.products order by id$$,
  array['40000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no ve los productos de Tenant B'
);

select results_eq(
  $$select id from public.modifier_groups order by id$$,
  array['50000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no ve los grupos de modificadores de Tenant B'
);

select results_eq(
  $$select id from public.dining_areas order by id$$,
  array['60000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no ve los sectores de Tenant B'
);

select results_eq(
  $$select id from public.dining_tables order by id$$,
  array['70000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no ve las mesas de Tenant B'
);

-- Aislamiento A -> B en escritura.
select throws_ok(
  $$insert into public.products (tenant_id, category_id, name, price_gs) values ('10000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Intruso', 1000)$$,
  '42501',
  null,
  'Tenant A no puede insertar un producto en Tenant B'
);

select results_eq(
  $$update public.products set name = 'Alterado' where id = '40000000-0000-0000-0000-000000000002' returning id$$,
  array[]::uuid[],
  'Tenant A no puede actualizar productos de Tenant B'
);

-- El ancla de dos columnas: la validación de una FK corre con privilegios
-- elevados y no consulta RLS, así que sin ella bastaría conocer el uuid ajeno.
select throws_ok(
  $$insert into public.products (tenant_id, category_id, name, price_gs) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', 'Categoría robada', 1000)$$,
  '23503',
  null,
  'un producto no puede referenciar una categoría de otro tenant'
);

select throws_ok(
  $$insert into public.modifier_options (tenant_id, modifier_group_id, name) values ('10000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', 'Opción robada')$$,
  '23503',
  null,
  'una opción no puede colgar de un grupo de otro tenant'
);

select throws_ok(
  $$insert into public.dining_tables (tenant_id, establishment_id, dining_area_id, code) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002', '99')$$,
  '23503',
  null,
  'una mesa no puede pertenecer a un sector de otro local'
);

-- Una fila no puede nacer archivada: no hay DELETE, así que quedaría inservible
-- y sin forma de recuperarla.
select throws_ok(
  $$insert into public.product_categories (tenant_id, name, status) values ('10000000-0000-0000-0000-000000000001', 'Nace muerta', 'archived')$$,
  '42501',
  null,
  'una categoría no puede insertarse ya archivada'
);

-- El tenant es inmutable.
select throws_ok(
  $$update public.products set tenant_id = '10000000-0000-0000-0000-000000000002' where id = '40000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'tenant_id is immutable',
  'un producto no se puede mover de tenant'
);

-- Sin borrado físico desde un cliente.
select throws_ok(
  $$delete from public.products where id = '40000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'un cliente no puede borrar productos'
);

-- Reglas del dominio que el esquema hace cumplir solo.
select throws_ok(
  $$insert into public.products (tenant_id, category_id, name, price_gs, iva_rate) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'IVA inventado', 1000, 21)$$,
  '23514',
  null,
  'el IVA solo puede ser 5% o 10%: no existe el 21% argentino'
);

select throws_ok(
  $$insert into public.products (tenant_id, category_id, name, price_gs) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Precio negativo', -1)$$,
  '23514',
  null,
  'un precio en guaraníes no puede ser negativo'
);

select throws_ok(
  $$insert into public.modifier_groups (tenant_id, name, selection_min, selection_max) values ('10000000-0000-0000-0000-000000000001', 'Rango imposible', 3, 1)$$,
  '23514',
  null,
  'un grupo no puede exigir más selecciones que las que permite'
);

select throws_ok(
  $$insert into public.product_categories (tenant_id, name) values ('10000000-0000-0000-0000-000000000001', 'Lomitos')$$,
  '23505',
  null,
  'no puede haber dos categorías vigentes con el mismo nombre'
);

reset role;

-- Archivar libera el nombre para una fila nueva.
update public.product_categories
set status = 'archived'
where id = '30000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$insert into public.product_categories (tenant_id, name) values ('10000000-0000-0000-0000-000000000001', 'Lomitos')$$,
  'archivar una categoría libera su nombre'
);

select isnt_empty(
  $$select id from public.product_categories where status = 'archived'$$,
  'una categoría archivada se sigue leyendo, para poder restaurarla'
);

reset role;

-- Un member es de solo lectura sobre el catálogo.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select isnt_empty(
  $$select id from public.products$$,
  'un member puede leer el catálogo de su tenant'
);

select throws_ok(
  $$insert into public.products (tenant_id, category_id, name, price_gs) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Alta de member', 1000)$$,
  '42501',
  null,
  'un member no puede dar de alta productos'
);

select results_eq(
  $$update public.products set name = 'Renombrado por member' where id = '40000000-0000-0000-0000-000000000001' returning id$$,
  array[]::uuid[],
  'un member no puede editar el catálogo'
);

select throws_ok(
  $$insert into public.dining_tables (tenant_id, establishment_id, dining_area_id, code) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '13')$$,
  '42501',
  null,
  'un member no puede crear mesas'
);

reset role;

select * from finish();

rollback;
