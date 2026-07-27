# Bloqueantes de producción

Nada se promueve a producción hasta que cada punto de esta lista tenga
**evidencia**, no una afirmación. Evidencia es una captura, un enlace a la
configuración, la salida de un comando o el número de un PR.

El estado de cada ítem se actualiza en este mismo archivo cuando se resuelve.

## Bloqueantes abiertos

### 1. No hay backend de rate limiting

`apps/api` construye en producción un limitador que **falla cerrado**: cada
request responde 503 auditado hasta que se configure un limitador realmente
compartido entre instancias. El limitador en memoria no sirve, porque cada
instancia serverless corre en su propio proceso y no limita nada.

- **Evidencia requerida:** política de rate limit aplicada a nivel plataforma, y
  el adaptador de `apps/api/lib/rate-limit/runtime-limiter.ts` apuntando a ella.
- Lo mismo aplica a las Server Actions de `apps/admin`.

### 2. `apps/web` no tiene CSP

El sitio público se sirve estático desde la CDN. Una CSP con nonce obligaría a
renderizar cada página por request. Se decidió **no** publicar una CSP con
`unsafe-inline`, porque aparentaría una protección que no existe.

- **Evidencia requerida:** o se acepta el renderizado dinámico y se usa la CSP
  con nonce como en `admin`, o se habilita SRI y se publica una CSP basada en
  hashes. Cualquiera de las dos cierra el punto; ninguna es "ya está".

### 3. Certificado F1 de facturación electrónica

Cada cliente necesita su propio certificado, vence cada año y se tramita
presencialmente. No hay nada implementado todavía.

- **Evidencia requerida:** procedimiento de alta, resguardo y renovación, más
  qué pasa con las ventas de un local cuyo certificado venció.

## Verificaciones antes de promover

### Repositorio

- [ ] Ruleset de GitHub sobre `main`: sin push directo, PR obligatorio, revisión
      requerida.
- [ ] Checks requeridos: `quality` y `database` en verde.
- [ ] Historial lineal y borrado automático de ramas mergeadas.

### Vercel

- [ ] Los cuatro proyectos con su Root Directory correcto y el Install Command
      `pnpm install --frozen-lockfile`.
- [ ] Rama de producción fijada en `main` en los cuatro.
- [ ] Deployment Protection activada en las previews.
- [ ] Variables cargadas por proyecto y por ambiente, sin ninguna compartida
      entre las cuatro apps.
- [ ] Ninguna preview apuntando a Supabase de producción. Verificado leyendo la
      variable, no asumido.

### Supabase

- [ ] Backups automáticos activados **y un restore ensayado** sobre un proyecto
      descartable, con la fecha del ensayo anotada.
- [ ] SMTP propio configurado. El SMTP de cortesía tiene límites que rompen el
      alta de clientes.
- [ ] Allowlist de redirecciones de Auth sin comodines en producción.
- [ ] Data API exponiendo solo el esquema `public`; el esquema `security` fuera.
- [ ] Sin deriva entre el esquema remoto y `supabase/migrations/`.
- [ ] `pnpm db:types:check` en verde contra el esquema promovido.

### Cabeceras y orígenes

- [ ] `admin` responde con CSP con nonce, sin `unsafe-inline` ni `unsafe-eval`.
- [ ] `api` responde con las cabeceras de endurecimiento y CORS solo para
      `ADMIN_ORIGIN` y `CAJA_ORIGIN`, con los valores reales de producción.
- [ ] `caja` se construyó con sus orígenes reales y su `index.html` tiene la
      CSP y ningún script inline.
- [ ] HSTS presente en los cuatro dominios de producción.

### Operación

- [ ] Dueño de rollback nombrado, con el procedimiento escrito y probado una vez.
- [ ] Los eventos de auditoría llegan a un destino consultable, no solo a stdout.
- [ ] Alguien que no escribió el código puede desplegar siguiendo
      [VERCEL.md](./VERCEL.md) sin preguntar nada.
