# Supabase local

Este directorio contiene únicamente la configuración local de Supabase para la
fundación del monorepo. No está vinculado con ningún proyecto remoto.

## Propósito

- `config.toml` permite al Data API exponer únicamente el schema `public`; el
  schema privado `security` nunca forma parte de esa lista.
- Auth local permite registro e inicio de sesión con email y contraseña. La
  confirmación de email está desactivada para facilitar el desarrollo local.
- `seed.sql` queda vacío hasta que la Task 5 cree el primer esquema.
- No se guardan claves ni secretos de producción en este directorio.

## URLs locales

Auth usa Admin como `site_url` y permite redirecciones exactas a:

- Web: `http://localhost:3000`.
- Admin: `http://localhost:3001`.
- Caja: `http://localhost:3002`.

Al probar un flujo de Auth, la aplicación correspondiente debe ejecutarse en el
puerto indicado.

## Requisitos

- Docker Desktop, o un motor compatible con la API de Docker, instalado y en
  ejecución.
- Node y `pnpm` según las versiones fijadas en la raíz del repositorio.
- Dependencias instaladas con `pnpm install`; esto instala Supabase CLI
  `2.109.1` como dependencia local. No hace falta iniciar sesión en Supabase.

Comprueba las herramientas antes de levantar los contenedores:

```bash
docker version
pnpm exec supabase --version
```

## Comandos útiles

Ejecuta siempre estos comandos desde la raíz del repositorio:

```bash
pnpm exec supabase start
pnpm exec supabase status
pnpm exec supabase db reset --local
pnpm test:db
pnpm exec supabase stop
```

El comando `pnpm test:db` ejecuta `supabase test db --local`. La suite pgTAP se
agregará en la Task 5; hasta entonces no hay tests de base de datos que correr.

## Límite remoto

No uses `supabase login`, `supabase link`, `supabase config push`, `--linked` ni
una URL de base remota desde este directorio. Los comandos de reset y test deben
conservar siempre `--local`.
