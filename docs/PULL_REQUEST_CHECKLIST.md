# Checklist de pull request

Se marca lo que aplica y se **borra** lo que no. Un ítem marcado sin haberlo
verificado es peor que un ítem sin marcar: hace creer que alguien miró.

Los contratos están en [SECURITY.md](./SECURITY.md),
[DATABASE.md](./DATABASE.md) y [ARCHITECTURE.md](./ARCHITECTURE.md).

## Tenant y datos

- [ ] Toda tabla nueva tiene RLS habilitada **y forzada**, con políticas por
      operación y `WITH CHECK` donde corresponde.
- [ ] La pertenencia a un tenant sale de las filas de membresía. No se leyó
      `user_metadata`, `app_metadata` ni ningún claim de rol del JWT.
- [ ] Hay una prueba pgTAP que demuestra que el tenant A no ve datos del B.
- [ ] Quitar una membresía surte efecto de inmediato, sin esperar a que venza
      un token.

## Entrypoints

- [ ] Cada verbo HTTP nuevo pasa por `defineAuthenticatedRoute` o
      `definePublicRoute` llamado directamente en el `route.ts`.
- [ ] Cada Server Action exportada pasa por `defineAuthenticatedAction`.
- [ ] Toda entrada se valida con Zod antes de tocar datos.
- [ ] La autorización de recurso corre dentro de la invocación, no solo en una
      pantalla o en el proxy.
- [ ] La respuesta es un DTO. No se devuelven filas crudas, tokens ni la
      credencial verificada.
- [ ] Una route pública nueva está en `security/public-entrypoints.json` con
      motivo, responsable y fecha de vencimiento.

## Secretos y configuración

- [ ] No hay `service_role`, `sb_secret_`, URL de base de datos, token de
      Vercel ni material de certificado en el diff.
- [ ] Las variables nuevas son públicas, están en `.env.example` y en la lista
      aprobada de `scripts/check-env-example.mjs`.
- [ ] Ningún origen nuevo de CORS o de CSP usa comodines.

## Observabilidad y límites

- [ ] Los rechazos quedan auditados con id de request, actor, acción, recurso y
      decisión, sin tokens ni payloads.
- [ ] Los logs nuevos no imprimen datos del cliente ni credenciales.
- [ ] Se tomó una decisión explícita de rate limit para el entrypoint nuevo, y
      está escrita.
- [ ] Una operación que se puede reintentar es idempotente, o se documenta por
      qué no hace falta.

## Base de datos

- [ ] La migración se aplicó sobre una base reconstruida desde cero, no sobre
      una que ya existía.
- [ ] Está escrito cómo se revierte, o por qué no se puede.
- [ ] `pnpm db:types:check` en verde: los tipos generados no quedaron viejos.
- [ ] Los tipos generados no se editaron a mano.

## Antes de pedir revisión

- [ ] `pnpm check` en verde localmente.
- [ ] Los tests nuevos fallan si se revierte el arreglo. Un test que pasa en
      los dos sentidos no prueba nada.
- [ ] Si el cambio toca algo de la lista de
      [PRODUCTION_READINESS.md](./PRODUCTION_READINESS.md), ese archivo se
      actualizó con la evidencia.
- [ ] Si el cambio mueve una frontera de arquitectura, hay un ADR nuevo en
      `docs/adr/`.
