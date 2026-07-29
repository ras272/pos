-- El certificado con el que se firma lo elige el servidor.
--
-- `documents.signing_certificate_id` es NOT NULL y el trigger de congelado
-- exige que apunte a un certificado activo, pero `security.issue_document`
-- nunca lo seteaba: no menciona ni la columna ni la tabla. La emision estaba
-- muerta y no se notaba porque ninguna prueba llegaba a emitir.
--
-- Se resuelve en un trigger y no en el RPC por dos razones. Una, es un valor del
-- servidor y este es el lugar donde el esquema ya congela los valores del
-- servidor. Dos, asi tambien lo obtiene cualquier camino futuro de insercion,
-- en vez de depender de que cada RPC nuevo se acuerde de buscarlo.
--
-- El nombre del trigger ordena antes que documents_freeze_fiscal_values, y para
-- triggers del mismo tipo y momento Postgres dispara por orden de nombre. La
-- columna se llena antes de que NOT NULL se evalue, porque los BEFORE corren
-- primero.

create function security.assign_signing_certificate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_certificate_id uuid;
begin
  if new.signing_certificate_id is not null then
    return new;
  end if;

  -- Se prefiere el certificado del propio local sobre uno del contribuyente,
  -- y entre varios vigentes el que vence mas tarde. El orden es total para que
  -- dos emisiones simultaneas elijan el mismo y el comprobante sea reproducible.
  select certificate.id
    into v_certificate_id
  from public.fiscal_certificates as certificate
  where certificate.tenant_id = new.tenant_id
    and certificate.status = 'active'
    and (
      certificate.establishment_id is null
      or certificate.establishment_id = new.establishment_id
    )
    and certificate.not_before <= new.business_date
    and certificate.expires_at > new.business_date
  order by
    (certificate.establishment_id is not null) desc,
    certificate.expires_at desc,
    certificate.id
  limit 1;

  if v_certificate_id is null then
    -- El F1 vence cada ano y se tramita presencialmente. Sin certificado
    -- vigente no se emite, y el mensaje tiene que decir eso y no un
    -- "violates not-null constraint".
    raise exception using
      errcode = 'P0001',
      message = 'no active signing certificate covers this business date';
  end if;

  new.signing_certificate_id := v_certificate_id;

  return new;
end;
$$;

create trigger documents_assign_signing_certificate
before insert on public.documents
for each row
execute function security.assign_signing_certificate();

revoke all on function security.assign_signing_certificate() from public, anon, authenticated;
