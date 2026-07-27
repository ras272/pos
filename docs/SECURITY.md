# Seguridad

La seguridad se aplica en cada invocación y termina en RLS. Un proxy, una ruta
oculta o un botón deshabilitado ayudan a la experiencia, pero nunca autorizan.

## Controles obligatorios de un entrypoint

Todo Route Handler, RPC o Server Action expuesto a red que lea o cambie datos
pasa por estos controles antes de ejecutar negocio. Que el acceso sea
autenticado no lo saca de esta categoría; sigue siendo un entrypoint de red:

1. Verificar la identidad con claims validados; una sesión sin verificar no es
   identidad de servidor.
2. Autorizar de forma explícita la acción sobre el recurso y tenant concretos.
3. Validar parámetros, body y límites con un schema Zod.
4. Ejecutar una decisión explícita de rate limit; la ausencia o falla del
   limitador cierra el acceso en producción.
5. Inyectar un cliente de datos con el JWT del usuario, nunca un cliente global
   privilegiado.
6. Emitir un evento de auditoría estructurado y redactado para allow, deny y
   error. Una falla de auditoría previa al handler cierra el acceso.
7. Ejecutar negocio y devolver solo un DTO definido, no filas arbitrarias.
8. Responder con errores seguros, request ID y sin tokens, payloads, SQL ni
   detalles internos.

Los entrypoints anónimos o sin autenticación requieren una excepción revisada,
con propósito, owner y vencimiento. Esa excepción no se extiende por defecto a
todo Server Action autenticado. La clave publicable puede estar en el navegador;
una clave `service_role`, `sb_secret_`, URL directa de Postgres o certificado
privado no.

## Server Actions

Una Server Action es un endpoint POST expuesto a red aunque solo la llame una
UI del repositorio. Por defecto es un entrypoint autenticado, no anónimo, y
debe cumplir los mismos controles anteriores, incluyendo authn, authz por
recurso, validación, rate limit y auditoría. La acción es un adaptador pequeño
y delega en un DAL marcado `server-only`; no contiene consultas sueltas ni
acepta `user_id`, `tenant_id` o rol como prueba de autoridad.

## Autoridad de tenant

`tenant_memberships` es la única autoridad para pertenencia y rol. Las policies
leen el usuario de `auth.uid()` y consultan la membresía vigente. Nunca se
autoriza con `user_metadata`, `app_metadata`, headers elegidos por el cliente ni
roles copiados al JWT. Así, una baja o suspensión entra en vigor inmediatamente
sin esperar a que venza un token.

El tenant solicitado tampoco se confía por venir en la URL o body: se valida
contra la membresía y el recurso real. La defensa final corresponde a las
policies descritas en [DATABASE.md](./DATABASE.md).

## Matriz inicial de roles

La matriz solo cubre el alcance aprobado hoy. La gestión de miembros requiere
un flujo auditado futuro; nadie escribe directamente la tabla de membresías.

| Operación                                        | `owner` | `admin` | `member` |
| ------------------------------------------------ | ------- | ------- | -------- |
| Leer tenant y establecimientos activos           | Sí      | Sí      | Sí       |
| Actualizar configuración del tenant              | Sí      | Sí      | No       |
| Actualizar configuración de establecimientos     | Sí      | Sí      | No       |
| Escribir directamente membresías                 | No      | No      | No       |
| Borrar o truncar datos físicamente desde cliente | No      | No      | No       |

`owner` y `admin` no son bypass de RLS: todas sus operaciones siguen limitadas
al tenant de una membresía activa. El sistema debe preservar al menos un owner
cuando se implemente el flujo de miembros.

## Secretos y logs

- Las variables públicas contienen solo URL de proyecto y clave publicable.
- Secretos viven únicamente en el proyecto Vercel y ambiente que los necesita.
- No se registran cookies, Authorization, JWT, claves, PII completa ni bodies.
- Un cliente privilegiado futuro debe ser server-only, no compartir cookies o
  Authorization del request y tener un caso de uso revisado por separado.
- CORS enumera orígenes exactos; no se usa `*` para entrypoints autenticados.
- Respuestas autenticadas usan `Cache-Control: private, no-store`.
