begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- Fixtures are inserted as the database owner. Every client assertion below
-- switches to the actual Supabase API role and supplies only a controlled sub.
insert into auth.users (id, email)
values
  ('00000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'owner-b@example.test'),
  ('00000000-0000-0000-0000-000000000003', 'admin-a@example.test'),
  ('00000000-0000-0000-0000-000000000004', 'member-a@example.test'),
  ('00000000-0000-0000-0000-000000000005', 'dual-admin@example.test'),
  ('00000000-0000-0000-0000-000000000006', 'not-a-member@example.test'),
  ('00000000-0000-0000-0000-000000000007', 'suspended-member@example.test'),
  ('00000000-0000-0000-0000-000000000008', 'suspended-tenant-owner@example.test'),
  ('00000000-0000-0000-0000-000000000009', 'removed-member@example.test'),
  ('00000000-0000-0000-0000-000000000010', 'bootstrap-caller@example.test'),
  ('00000000-0000-0000-0000-000000000011', 'rate-limited-caller@example.test');

insert into public.tenants (id, name, status)
values
  ('10000000-0000-0000-0000-000000000001', 'Tenant A', 'active'),
  ('10000000-0000-0000-0000-000000000002', 'Tenant B', 'active'),
  ('10000000-0000-0000-0000-000000000003', 'Tenant suspendido', 'suspended');

insert into public.tenant_memberships (tenant_id, user_id, role, status)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'member', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000005', 'admin', 'active'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000005', 'admin', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000007', 'member', 'suspended'),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000008', 'owner', 'active'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000009', 'member', 'active');

insert into public.establishments (id, tenant_id, name, status)
values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Local A', 'active'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Local B', 'active');

-- A user without an active membership cannot read or write a tenant row.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000006', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000006","role":"authenticated","app_metadata":{"tenant_role":"owner"},"user_metadata":{"tenant_role":"owner"}}',
  true
);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'un usuario sin membresía no puede leer tenants'
);

select throws_ok(
  $$insert into public.establishments (tenant_id, name) values ('10000000-0000-0000-0000-000000000001', 'Intento ajeno')$$,
  '42501',
  null,
  'un usuario sin membresía no puede crear establecimientos'
);

reset role;

-- Tenant A cannot observe or mutate Tenant B, including an attempted delete.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select results_eq(
  $$select id from public.tenants order by id$$,
  array['10000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A solo puede leer su tenant'
);

select results_eq(
  $$select id from public.establishments order by id$$,
  array['20000000-0000-0000-0000-000000000001'::uuid],
  'Tenant A no puede observar establecimientos de Tenant B'
);

select lives_ok(
  $$insert into public.establishments (id, tenant_id, name) values ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'Local A adicional')$$,
  'un owner puede crear un establecimiento de su tenant'
);

select throws_ok(
  $$insert into public.establishments (tenant_id, name) values ('10000000-0000-0000-0000-000000000002', 'Intento en Tenant B')$$,
  '42501',
  null,
  'Tenant A no puede insertar en Tenant B'
);

select results_eq(
  $$update public.establishments set name = 'Local B alterado' where id = '20000000-0000-0000-0000-000000000002' returning id$$,
  array[]::uuid[],
  'Tenant A no puede actualizar establecimientos de Tenant B'
);

select throws_ok(
  $$delete from public.establishments where id = '20000000-0000-0000-0000-000000000002'$$,
  '42501',
  null,
  'Tenant A no recibe privilegio DELETE sobre Tenant B'
);

reset role;

-- A member retains read-only access even when the client chooses an update.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
set local role authenticated;

select results_eq(
  $$select id from public.establishments order by id$$,
  array['20000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000003'::uuid],
  'un member puede leer establecimientos activos de su tenant'
);

select results_eq(
  $$update public.tenants set name = 'Tenant A por member' where id = '10000000-0000-0000-0000-000000000001' returning id$$,
  array[]::uuid[],
  'un member no puede actualizar la configuración del tenant'
);

select results_eq(
  $$update public.establishments set name = 'Local A por member' where id = '20000000-0000-0000-0000-000000000001' returning id$$,
  array[]::uuid[],
  'un member no puede actualizar establecimientos'
);

select throws_ok(
  $$insert into public.establishments (tenant_id, name) values ('10000000-0000-0000-0000-000000000001', 'Local por member')$$,
  '42501',
  null,
  'un member no puede crear establecimientos'
);

reset role;

-- An admin has the same scoped settings access that a member must not gain.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
set local role authenticated;

select results_eq(
  $$update public.tenants set name = 'Tenant A administrado' where id = '10000000-0000-0000-0000-000000000001' returning id$$,
  array['10000000-0000-0000-0000-000000000001'::uuid],
  'un admin puede actualizar la configuración de su tenant'
);

select results_eq(
  $$update public.establishments set name = 'Local A administrado' where id = '20000000-0000-0000-0000-000000000001' returning id$$,
  array['20000000-0000-0000-0000-000000000001'::uuid],
  'un admin puede actualizar un establecimiento de su tenant'
);

reset role;

-- Direct membership management is denied even to an owner.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
set local role authenticated;

select throws_ok(
  $$insert into public.tenant_memberships (tenant_id, user_id, role) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000006', 'member')$$,
  '42501',
  null,
  'un owner no puede insertar membresías directamente'
);

select throws_ok(
  $$update public.tenant_memberships set role = 'admin' where tenant_id = '10000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'un owner no puede actualizar membresías directamente'
);

select throws_ok(
  $$delete from public.tenant_memberships where tenant_id = '10000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'un owner no puede borrar membresías directamente'
);

reset role;

-- Even an admin in both tenants cannot reassign a tenant-owned row.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
set local role authenticated;

select throws_like(
  $$update public.establishments set tenant_id = '10000000-0000-0000-0000-000000000002' where id = '20000000-0000-0000-0000-000000000001'$$,
  'tenant_id is immutable',
  'una doble membresía no permite reasignar un establecimiento entre tenants'
);

reset role;

-- Role and tenant suspension are evaluated by each policy invocation.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000007', true);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'una membresía suspendida no concede acceso'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000008', true);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'un tenant suspendido no concede acceso'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
set local role authenticated;

select results_eq(
  $$select id from public.tenants order by id$$,
  array['10000000-0000-0000-0000-000000000001'::uuid],
  'una membresía activa concede acceso antes de la baja'
);

reset role;
update public.tenant_memberships
set status = 'suspended'
where tenant_id = '10000000-0000-0000-0000-000000000001'
  and user_id = '00000000-0000-0000-0000-000000000009';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'suspender una membresía se aplica sin esperar un JWT nuevo'
);

reset role;
delete from public.tenant_memberships
where tenant_id = '10000000-0000-0000-0000-000000000001'
  and user_id = '00000000-0000-0000-0000-000000000009';

select results_eq(
  $$select count(*) from public.tenant_memberships where tenant_id = '10000000-0000-0000-0000-000000000001' and user_id = '00000000-0000-0000-0000-000000000009'$$,
  array[0::bigint],
  'la baja elimina la membresía autoritativa'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000009', true);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'la baja de membresía se aplica sin esperar un JWT nuevo'
);

reset role;
update public.tenants
set status = 'suspended'
where id = '10000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
set local role authenticated;

select is_empty(
  $$select id from public.tenants$$,
  'suspender un tenant se aplica sin esperar un JWT nuevo'
);

reset role;

-- Only authenticated callers can bootstrap. The owner row and first
-- establishment are created atomically from auth.uid(), never caller inputs.
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$select * from public.bootstrap_tenant('Tenant anon', 'Local anon')$$,
  '42501',
  null,
  'anon no puede ejecutar el bootstrap'
);

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', true);
set local role authenticated;

select lives_ok(
  $$select * from public.bootstrap_tenant('Tenant bootstrap', 'Local inicial')$$,
  'el caller autenticado puede bootstrappear su propio tenant'
);

select results_eq(
  $$select count(*) from public.tenants where name = 'Tenant bootstrap'$$,
  array[1::bigint],
  'el bootstrap crea exactamente un tenant visible al caller'
);

reset role;

select results_eq(
  $$select role::text from public.tenant_memberships tm join public.tenants t on t.id = tm.tenant_id where t.name = 'Tenant bootstrap' and tm.user_id = '00000000-0000-0000-0000-000000000010'$$,
  array['owner'::text],
  'el bootstrap crea solamente la membresía owner del caller'
);

select results_eq(
  $$select count(*) from public.establishments e join public.tenants t on t.id = e.tenant_id where t.name = 'Tenant bootstrap' and e.name = 'Local inicial'$$,
  array[1::bigint],
  'el bootstrap crea el establecimiento inicial'
);

select results_eq(
  $$select audit.actor_id from security.tenant_bootstrap_audit audit join public.tenants tenant on tenant.id = audit.tenant_id where tenant.name = 'Tenant bootstrap'$$,
  array['00000000-0000-0000-0000-000000000010'::uuid],
  'el audit privado atribuye el bootstrap exitoso al caller autenticado'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', true);
set local role authenticated;

select throws_ok(
  $$select * from security.tenant_bootstrap_audit$$,
  '42501',
  null,
  'el caller autenticado no puede leer el audit privado'
);

reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', true);
set local role authenticated;

select throws_like(
  $$select * from public.bootstrap_tenant('   ', 'Local inválido')$$,
  'tenant name must not be blank',
  'el bootstrap rechaza nombres de tenant inválidos'
);

reset role;

select results_eq(
  $$select count(*) from public.tenants where name = '   '$$,
  array[0::bigint],
  'un bootstrap con validación previa no crea un tenant'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', true);
set local role authenticated;

select throws_like(
  $$select * from public.bootstrap_tenant(repeat('x', 121), 'Local demasiado largo')$$,
  'tenant name must be between 1 and 120 characters',
  'el bootstrap limita el largo del nombre de tenant'
);

select lives_ok(
  $$select * from public.bootstrap_tenant('  Tenant normalizado  ', '  Local normalizado  ')$$,
  'el bootstrap normaliza nombres válidos antes de persistirlos'
);

reset role;

select results_eq(
  $$select count(*) from public.tenants where name = 'Tenant normalizado'$$,
  array[1::bigint],
  'el bootstrap persiste el nombre de tenant sin espacios de borde'
);

select results_eq(
  $$select count(*) from public.establishments where name = 'Local normalizado'$$,
  array[1::bigint],
  'el bootstrap persiste el nombre de establecimiento sin espacios de borde'
);

create function public.fail_bootstrap_establishment_probe()
returns trigger
language plpgsql
as $$
begin
  if new.name = 'Local que fuerza rollback' then
    raise exception 'bootstrap establishment probe failure';
  end if;

  return new;
end;
$$;

create trigger fail_bootstrap_establishment_probe
before insert on public.establishments
for each row
execute function public.fail_bootstrap_establishment_probe();

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', true);
set local role authenticated;

select throws_like(
  $$select * from public.bootstrap_tenant('Tenant que debe revertir', 'Local que fuerza rollback')$$,
  'bootstrap establishment probe failure',
  'un fallo después de crear tenant y membresía revierte todo el bootstrap'
);

reset role;

select results_eq(
  $$select count(*) from public.tenants where name = 'Tenant que debe revertir'$$,
  array[0::bigint],
  'un bootstrap fallido después del primer insert no deja tenant parcial'
);

select results_eq(
  $$select count(*) from public.tenant_memberships membership join public.tenants tenant on tenant.id = membership.tenant_id where tenant.name = 'Tenant que debe revertir'$$,
  array[0::bigint],
  'un bootstrap fallido después del primer insert no deja membresía parcial'
);

select results_eq(
  $$select count(*) from public.establishments where name = 'Local que fuerza rollback'$$,
  array[0::bigint],
  'un bootstrap fallido después del primer insert no deja establecimiento parcial'
);

-- Foundation anti-burst policy: invalid requests do not consume the quota, then
-- only three successful bootstraps may be committed for one actor each hour.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000011', true);
set local role authenticated;

select throws_like(
  $$select * from public.bootstrap_tenant('   ', 'Local inválido para cuota')$$,
  'tenant name must not be blank',
  'un intento inválido no consume la cuota de bootstrap'
);

select lives_ok(
  $$select * from public.bootstrap_tenant('Tenant cuota 1', 'Local cuota 1')$$,
  'el primer bootstrap exitoso entra en la cuota'
);

select lives_ok(
  $$select * from public.bootstrap_tenant('Tenant cuota 2', 'Local cuota 2')$$,
  'el segundo bootstrap exitoso entra en la cuota'
);

select lives_ok(
  $$select * from public.bootstrap_tenant('Tenant cuota 3', 'Local cuota 3')$$,
  'el tercer bootstrap exitoso entra en la cuota'
);

select throws_ok(
  $$select * from public.bootstrap_tenant('Tenant cuota 4', 'Local cuota 4')$$,
  'P0001',
  'tenant bootstrap rate limit exceeded',
  'el cuarto bootstrap en una hora se deniega con error estable'
);

reset role;

select results_eq(
  $$select count(*) from security.tenant_bootstrap_audit where actor_id = '00000000-0000-0000-0000-000000000011'$$,
  array[3::bigint],
  'solo bootstrap exitosos consumen la cuota y escriben audit'
);

select results_eq(
  $$select count(*) from public.tenants where name = 'Tenant cuota 4'$$,
  array[0::bigint],
  'el bootstrap limitado revierte el tenant que habría creado'
);

select * from finish();
rollback;
