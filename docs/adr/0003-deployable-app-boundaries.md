# ADR 0003: Límites de aplicaciones desplegables

- Estado: aceptado
- Fecha: 2026-07-26

## Contexto

Marketing, backoffice, POS offline y API tienen públicos, runtimes y riesgos
distintos. Un único deploy mezclaría caché público, cookies, secretos y permisos;
también permitiría que el POS de navegador importe código solo de servidor.

## Decisión

Se mantienen cuatro aplicaciones y proyectos Vercel independientes:

- `web`: marketing público/estático en Next.js;
- `admin`: UI autenticada y Server Actions en Next.js;
- `caja`: Vite/React browser-only y offline-first;
- `api`: único host Next.js de endpoints HTTP de negocio.

Apps pueden importar packages, packages no importan apps. Los exports de
navegador y servidor permanecen separados y los adaptadores de Next son locales
a su aplicación.

## Consecuencias

- Cada deploy tiene ambientes, dominios, previews y secretos propios.
- CORS entre caja/admin y API usa orígenes exactos.
- La caja puede compilarse sin módulos Node o secretos.
- Duplicar un handler de negocio en `web` o `admin` contradice esta decisión; un
  caso excepcional requiere revisión y un ADR reemplazante.
