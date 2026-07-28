begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select no_plan();

-- MARCADOR_ESTRUCTURAL
-- Ningun nombre de constraint quedo truncado en los 63 caracteres de Postgres. Un identificador de exactamente 63 caracteres es la firma de un truncado silencioso, que rompe todo assert por nombre.
select ok(
  not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid = c.conrelid
    join pg_catalog.pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and pg_catalog.char_length(c.conname::text) >= 63
  ),
  'ningun nombre de constraint del dominio quedo truncado en 63 caracteres'
);

-- El check de largo del mensaje de respuesta existe con su nombre completo: es el identificador que medido con el prefijo sifen_ daba 64 caracteres.
select has_check('public', 'document_transmission_events', 'document_transmission_events tiene checks de largo de respuesta');
select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.document_transmission_events'::regclass
      and c.conname = 'document_transmission_events_response_message_length_check'
  ),
  'el check de largo del mensaje de respuesta conserva su nombre completo'
);

-- Las pruebas que ejercitan security.register_sale viven en 007, junto con los
-- RPC que las hacen posibles: acá todavía no existe la funcion que congela.

-- El cliente solo lee: cero policies de escritura y cero grants de escritura en las siete tablas.
select policies_are('public', 'documents', array['documents_select_active_members'], 'documents solo tiene policy de lectura');
select policies_are('public', 'payments', array['payments_select_active_members'], 'payments solo tiene policy de lectura');
select table_privs_are('public', 'documents', 'authenticated', array['SELECT']::text[], 'authenticated solo recibe SELECT en documents');
select table_privs_are('public', 'documents', 'anon', array[]::text[], 'anon no recibe acceso a documents');
select table_privs_are('public', 'payment_reversals', 'authenticated', array['SELECT']::text[], 'authenticated solo recibe SELECT en payment_reversals');


select * from finish();

rollback;
