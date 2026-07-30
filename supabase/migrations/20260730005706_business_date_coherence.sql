-- La jornada operativa tiene que ser coherente con la fecha de firma.
--
-- El umbral del comprobante innominado se resuelve por business_date, y
-- business_date entraba como parametro libre del dispositivo, sin relacion con
-- signed_at ni con el turno. Solo tenia que caer dentro de la vigencia del
-- timbrado, que es de un ano. O sea: el dispositivo elegia que umbral se le
-- aplicaba, y podia emitir innominado por encima de los 7.000.000.

CREATE OR REPLACE FUNCTION security.freeze_document_fiscal_values()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_establishment_code text;
  v_expedition_point_code text;
  v_timbrado_number text;
  v_timbrado_valid_from date;
  v_timbrado_valid_to date;
  v_range_from bigint;
  v_range_to bigint;
  v_threshold_gs bigint;
  v_threshold_from date;
  v_issuer_ruc text;
  v_issuer_ruc_dv smallint;
  v_issuer_legal_name text;
  v_certificate_expires_at date;
begin
  -- El reloj de la tablet no puede correr un plazo legal. El futuro nunca es
  -- legitimo; el pasado si, y es exactamente el caso que hay que reportar.
  new.received_at := pg_catalog.now();

  if new.signed_at > new.received_at + interval '5 minutes' then
    raise exception using
      errcode = 'P0001',
      message = 'signed_at cannot be in the future';
  end if;

  if new.signed_at < new.received_at - interval '30 days' then
    raise exception using
      errcode = 'P0001',
      message = 'signed_at is older than the reportable window';
  end if;

  new.transmit_deadline_at := new.signed_at + interval '72 hours';

  -- La jornada operativa no puede alejarse de la fecha de firma. El umbral del
  -- comprobante innominado se resuelve por business_date, y business_date entraba
  -- como parametro libre del cliente: un dispositivo podia declarar una jornada
  -- de hace dos anos, caer bajo el umbral viejo de 35.000.000 y emitir innominado
  -- por encima de los 7.000.000 de hoy.
  --
  -- Un dia de tolerancia porque el bar que cierra a las 3 de la manana sigue en la
  -- jornada anterior. Va en el trigger y no en un check porque convertir a fecha
  -- local no es IMMUTABLE.
  if new.business_date < ((new.signed_at at time zone 'America/Asuncion')::date - 1)
     or new.business_date > ((new.signed_at at time zone 'America/Asuncion')::date + 1) then
    raise exception using
      errcode = 'P0001',
      message = 'business_date is not consistent with signed_at';
  end if;

  select tenant.ruc, tenant.ruc_dv, tenant.legal_name
    into v_issuer_ruc, v_issuer_ruc_dv, v_issuer_legal_name
  from public.tenants as tenant
  where tenant.id = new.tenant_id;

  if v_issuer_ruc is null or v_issuer_ruc_dv is null or v_issuer_legal_name is null then
    raise exception using
      errcode = 'P0001',
      message = 'issuer fiscal identity is not configured';
  end if;

  select establishment.establishment_code
    into v_establishment_code
  from public.establishments as establishment
  where establishment.id = new.establishment_id
    and establishment.tenant_id = new.tenant_id;

  select pos_terminal.expedition_point_code
    into v_expedition_point_code
  from public.pos_terminals as pos_terminal
  where pos_terminal.id = new.pos_terminal_id
    and pos_terminal.establishment_id = new.establishment_id;

  if v_establishment_code is null or v_expedition_point_code is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal codes are not configured';
  end if;

  select timbrado.number, timbrado.valid_from, timbrado.valid_to
    into v_timbrado_number, v_timbrado_valid_from, v_timbrado_valid_to
  from public.fiscal_timbrados as timbrado
  where timbrado.id = new.timbrado_id
    and timbrado.tenant_id = new.tenant_id
    and timbrado.status = 'active';

  if v_timbrado_number is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal stamp is not active';
  end if;

  -- La fila del contador que CONTIENE el numero, no la vigente: renovar el rango
  -- no puede dejar irrecuperable un comprobante ya impreso del rango anterior.
  select counter.range_from, counter.range_to
    into v_range_from, v_range_to
  from public.document_counters as counter
  where counter.pos_terminal_id = new.pos_terminal_id
    and counter.document_type = new.document_type
    and counter.timbrado_id = new.timbrado_id
    and new.number between counter.range_from and counter.range_to;

  if v_range_from is null then
    raise exception using
      errcode = 'P0001',
      message = 'document number outside every authorized range';
  end if;

  -- Por la fecha de la VENTA, nunca por now(): con 72 h de ventana, sincronizar
  -- despues de un decreto es el caso ordinario. Una venta legal bajo el umbral
  -- viejo tiene que poder guardarse, y una posterior al decreto no.
  select threshold.anonymous_buyer_threshold_gs, threshold.effective_from
    into v_threshold_gs, v_threshold_from
  from public.fiscal_thresholds as threshold
  where threshold.tenant_id = new.tenant_id
    and threshold.effective_from <= new.business_date
    and (threshold.effective_to is null or new.business_date < threshold.effective_to)
  order by threshold.effective_from desc
  limit 1;

  if v_threshold_gs is null then
    raise exception using
      errcode = 'P0001',
      message = 'fiscal threshold is not configured';
  end if;

  select certificate.expires_at
    into v_certificate_expires_at
  from public.fiscal_certificates as certificate
  where certificate.id = new.signing_certificate_id
    and certificate.tenant_id = new.tenant_id
    and certificate.status = 'active';

  if v_certificate_expires_at is null then
    raise exception using
      errcode = 'P0001',
      message = 'signing certificate is not active';
  end if;

  -- Una divergencia significa que el papel impreso y el servidor no dicen lo
  -- mismo. Se rechaza, no se corrige en silencio: hay que enterarse antes de
  -- transmitir, no despues del rechazo de SIFEN.
  if (new.establishment_code is not null and new.establishment_code is distinct from v_establishment_code)
    or (new.expedition_point_code is not null and new.expedition_point_code is distinct from v_expedition_point_code)
    or (new.timbrado_number is not null and new.timbrado_number is distinct from v_timbrado_number)
    or (new.authorized_range_from is not null and new.authorized_range_from is distinct from v_range_from)
    or (new.authorized_range_to is not null and new.authorized_range_to is distinct from v_range_to)
    or (new.anonymous_buyer_threshold_gs is not null and new.anonymous_buyer_threshold_gs is distinct from v_threshold_gs)
  then
    raise exception using
      errcode = 'P0001',
      message = 'frozen fiscal values do not match the server';
  end if;

  new.establishment_code := v_establishment_code;
  new.expedition_point_code := v_expedition_point_code;
  new.timbrado_number := v_timbrado_number;
  new.timbrado_valid_from := v_timbrado_valid_from;
  new.timbrado_valid_to := v_timbrado_valid_to;
  new.authorized_range_from := v_range_from;
  new.authorized_range_to := v_range_to;
  new.anonymous_buyer_threshold_gs := v_threshold_gs;
  new.anonymous_threshold_from := v_threshold_from;
  new.issuer_ruc := v_issuer_ruc;
  new.issuer_ruc_dv := v_issuer_ruc_dv;
  new.issuer_legal_name := v_issuer_legal_name;
  new.certificate_expires_at := v_certificate_expires_at;

  if new.buyer_doc_type = 'RUC'
     and new.buyer_ruc_dv is distinct from security.ruc_check_digit(new.buyer_doc_number) then
    raise exception using
      errcode = 'P0001',
      message = 'buyer ruc check digit is invalid';
  end if;

  return new;
end;
$function$;
