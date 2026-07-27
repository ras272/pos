# Secure SaaS Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a modular, documented, RLS-first foundation for the cloud POS so future UI and endpoint work starts secure by default.

**Architecture:** Supabase Postgres migrations are the sole database source of truth. `apps/web` remains public marketing, `apps/admin` is the authenticated Next.js backoffice, `apps/caja` is the Vite browser POS, and `apps/api` is the only Next.js host for business HTTP endpoints. Browser and SSR clients use generated types and a publishable key so RLS remains the tenant boundary; secret keys are prohibited until a reviewed server-only use case exists. Shared packages are split into browser-safe and server-only subpath exports with no mixed barrel.

**Tech Stack:** pnpm/turbo, Node 24.18.0 LTS, Next.js 16.2.6, Vite/React, Supabase Auth/Postgres, PostgreSQL RLS, pgTAP, TypeScript, Zod, Vitest, GitHub Actions, Vercel.

---

## Chunk 1: Repository contracts and tooling

### Task 1: Record architectural and security decisions

**Files:**

- Create: `docs/ARCHITECTURE.md`
- Create: `docs/SECURITY.md`
- Create: `docs/DATABASE.md`
- Create: `docs/DEVELOPMENT.md`
- Create: `docs/adr/0001-supabase-sql-over-drizzle.md`
- Create: `docs/adr/0002-rls-tenant-boundary.md`
- Create: `docs/adr/0003-deployable-app-boundaries.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1:** Document deployables: `web` is public/static marketing; `admin` is authenticated Next UI; `caja` is browser-only Vite; `api` owns HTTP business endpoints. Each is a separate Vercel project and environment boundary.
- [ ] **Step 2:** Document dependency direction: apps may import packages; packages never import apps; `caja` may import only browser-safe exports; Next SSR/proxy adapters remain app-local; only `api` may contain `route.ts` business handlers.
- [ ] **Step 3:** Define mandatory endpoint controls: verified identity, explicit resource authorization, Zod input validation, user-scoped data client, DTO output, safe errors, audit event, explicit rate-limit decision, and no secret-key exposure.
- [ ] **Step 4:** Define Server Actions as public POST entrypoints requiring the same controls and delegation to a `server-only` DAL.
- [ ] **Step 5:** Document SQL migrations as canonical and explain why Drizzle is deferred: dual migration sources and direct connections can bypass the JWT/RLS context.
- [ ] **Step 6:** Define tenant invariants, RLS policy conventions, grants, function safety, indexes, soft deletion, and migration review rules.
- [ ] **Step 7:** Define the initial role matrix: `owner` and `admin` can update tenant/establishment settings; `member` is read-only. Membership rows are authoritative and JWT metadata is never used for tenant authorization.
- [ ] **Step 8:** Add concise agent rules that point to authoritative docs instead of duplicating them.
- [ ] **Step 9:** Review every document for contradictions with `packages/ui/DESIGN.md` and the Paraguay constraints.
- [ ] **Step 10:** Run `pnpm prettier --check docs AGENTS.md CLAUDE.md README.md` and expect exit 0.
- [ ] **Step 11:** Commit the documentation contract.

### Task 2: Upgrade and normalize root tooling

**Files:**

- Modify: `package.json`
- Modify: `pnpm-lock.yaml`
- Modify: `turbo.json`
- Modify: `.gitignore`
- Create: `.env.example`
- Create: `.node-version`
- Create: `scripts/check-architecture.mjs`
- Create: `scripts/check-env-example.mjs`
- Create: `scripts/check-file-size.mjs`
- Create: `scripts/check-entrypoints.mjs`
- Create: `scripts/check-workflows.mjs`
- Create: `scripts/security-patterns.mjs`
- Test: `scripts/__tests__/architecture.test.ts`
- Test: `scripts/__tests__/security-patterns.test.ts`
- Test: `scripts/__tests__/entrypoints.test.ts`
- Create: `security/file-size-exceptions.json`
- Create: `security/public-entrypoints.json`

- [ ] **Step 1:** Write failing Vitest tests for forbidden `service_role`/`sb_secret_`/database/Vercel secrets, unsafe package imports, unwrapped Route Handlers and Server Actions, and oversized source modules.
- [ ] **Step 2:** Run the focused tests and confirm they fail because the scripts do not exist.
- [ ] **Step 3:** Pin Node and CI exactly to 24.18.0, pin Supabase CLI and Vitest versions, and add root `format:check`, `test`, `test:db`, `db:types`, `db:types:check`, `security`, and `check` scripts.
- [ ] **Step 4:** Implement AST-based entrypoint checks: every HTTP verb export must wrap with `defineAuthenticatedRoute` or `definePublicRoute`; every exported function in a `use server` module must wrap with `defineAuthenticatedAction`.
- [ ] **Step 5:** Require each `definePublicRoute` in `security/public-entrypoints.json` with method, path, reason, owner, review/expiry date, and explicit confirmation that it exposes no tenant data and performs no mutation unless separately justified. Unlisted or expired public routes fail.
- [ ] **Step 6:** Enforce a 250-line limit for hand-written `.ts/.tsx/.mjs` files. Exclude generated database types, shadcn component sources, tests, migrations, and docs. Exceptions require `path`, `reason`, `owner`, and ISO `expiresOn`; expired entries fail.
- [ ] **Step 7:** Remove warning-only lint behavior for first-party app/package code or make CI fail on warnings; preserve existing generated UI warnings as a documented temporary baseline.
- [ ] **Step 8:** Run focused tests until green, then run `pnpm check`.
- [ ] **Step 9:** Commit tooling and architecture gates.

## Chunk 2: Database and tenant isolation

### Task 3: Scaffold deployable application boundaries

**Files:**

- Create: `apps/admin/package.json`
- Create: `apps/admin/next.config.ts`
- Create: `apps/admin/tsconfig.json`
- Create: `apps/admin/app/layout.tsx`
- Create: `apps/admin/app/page.tsx`
- Create: `apps/api/package.json`
- Create: `apps/api/next.config.ts`
- Create: `apps/api/tsconfig.json`
- Create: `apps/api/app/layout.tsx`
- Create: `apps/api/app/page.tsx`
- Create: `apps/caja/package.json`
- Create: `apps/caja/vite.config.ts`
- Create: `apps/caja/tsconfig.json`
- Create: `apps/caja/index.html`
- Create: `apps/caja/src/main.tsx`
- Create: `apps/caja/src/app.tsx`
- Modify: `turbo.json`

- [ ] **Step 1:** Add minimal build/typecheck/lint/format scripts and exact framework versions; add no feature UI or router yet.
- [ ] **Step 2:** Keep each app shell under 100 lines and import only `@workspace/ui` styling/components needed for a neutral placeholder.
- [ ] **Step 3:** Configure Turbo outputs for `.next/**` and `dist/**`.
- [ ] **Step 4:** Run `pnpm install`, `pnpm lint`, `pnpm typecheck`, and `pnpm build`; expect all four apps to succeed.
- [ ] **Step 5:** Run `pnpm security`; expect package-boundary checks to prove `caja` cannot import server-only exports.
- [ ] **Step 6:** Commit deployable boundaries.

### Task 4: Initialize Supabase local development

**Files:**

- Create: `supabase/config.toml`
- Create: `supabase/seed.sql`
- Create: `supabase/README.md`
- Create: `supabase/.gitignore`

- [ ] **Step 1:** Use `pnpm exec supabase --help` and `pnpm exec supabase init --help`; do not guess CLI flags.
- [ ] **Step 2:** Initialize the local project without linking or mutating the existing unrelated Supabase project.
- [ ] **Step 3:** Configure local Auth for email/password development, explicit site/redirect URLs, no production secrets, and an explicit Data API schema allowlist containing only `public`; exclude the private `security` schema.
- [ ] **Step 4:** Document Docker and CLI prerequisites plus reset/test commands.
- [ ] **Step 5:** Validate the generated config with the installed CLI.
- [ ] **Step 6:** Commit local Supabase configuration.

### Task 5: Test and implement the tenancy schema

**Files:**

- Create: `supabase/tests/database/001_tenant_isolation.test.sql`
- Create: `supabase/tests/database/002_database_security.test.sql`
- Create: migration via `pnpm exec supabase migration new secure_tenant_foundation`
- Modify: generated migration file only after the failing test exists

- [ ] **Step 1:** Write pgTAP fixtures as database owner, then switch to `anon`/`authenticated` with controlled `sub` claims. Cover nonmember denial, A→B isolation for every operation, low-role denial, direct membership mutation denial, dual-member tenant reassignment, suspended tenant/membership denial, and no DELETE/TRUNCATE privileges.
- [ ] **Step 2:** Write structural pgTAP tests requiring RLS enabled+forced on every project-owned exposed table, no `PUBLIC EXECUTE`, explicit schema/table/routine grants, indexed foreign keys, and no unsafe exposed views/functions.
- [ ] **Step 3:** Start local Supabase, run `pnpm exec supabase db reset --local`, then `pnpm exec supabase test db --local`; confirm RED because the schema is missing.
- [ ] **Step 4:** Create `tenant_role` (`owner`, `admin`, `member`), `tenants`, `tenant_memberships`, and `establishments` with UUID keys, timestamps, active/suspended status checks, composite uniqueness, and indexed foreign keys.
- [ ] **Step 5:** Add a private `security` schema and a `STABLE SECURITY DEFINER` role helper with empty search path, qualified identifiers, no dynamic SQL, explicit `auth.uid()` check, no Data API exposure, and only the minimum execute privilege needed by policies.
- [ ] **Step 6:** Implement a two-layer atomic bootstrap: non-exposed `security.bootstrap_tenant(...)` is `SECURITY DEFINER`, uses empty search path/qualified names/no dynamic SQL, derives `auth.uid()`, and creates tenant + caller owner membership + first establishment; exposed `public.bootstrap_tenant(...)` is `SECURITY INVOKER` and only delegates to the private function. Neither accepts user ID or role. Revoke execute from `PUBLIC`/`anon`; grant only the exact schema usage/function execute privileges required by `authenticated`.
- [ ] **Step 7:** Add immutable-tenant triggers for every tenant-owned table. Direct INSERT/UPDATE/DELETE on memberships stays denied; a future audited membership RPC must preserve at least one owner.
- [ ] **Step 8:** Revoke defaults for schemas/tables/sequences/routines, deny schema `CREATE`, set restrictive default privileges for future objects, grant exact SELECT/INSERT/UPDATE operations, enable+force RLS, and create operation-specific policies with `USING` and `WITH CHECK`.
- [ ] **Step 9:** Make membership rows the sole tenant authorization source. Never use `user_metadata`, `app_metadata`, or other JWT role claims for tenant membership; removal/suspension must take effect immediately through RLS.
- [ ] **Step 10:** Test bootstrap denial for anon, caller-only owner creation, initial establishment, invalid-input rollback, absence of user/role parameters, and continued denial of direct membership writes. Test that Data API exposed schemas exclude `security` and privileged helpers cannot be invoked as RPCs.
- [ ] **Step 11:** Run clean reset + pgTAP until green. Exact expected tail: `Result: PASS` with no failed tests.
- [ ] **Step 12:** Commit schema and isolation tests.

### Task 6: Generate and expose database types

**Files:**

- Create: `packages/database/package.json`
- Create: `packages/database/tsconfig.json`
- Create: `packages/database/eslint.config.js`
- Create: `packages/database/src/database.types.ts`
- Create: `packages/database/src/index.ts`
- Create: `packages/database/README.md`
- Test: `packages/database/src/index.test-d.ts`

- [ ] **Step 1:** Add a type-level test importing the planned `Database` export and verify it fails.
- [ ] **Step 2:** Generate types from local Supabase; do not hand-maintain table types.
- [ ] **Step 3:** Export only types from `@workspace/database` so it cannot open connections or carry secrets.
- [ ] **Step 4:** Add lint/typecheck scripts and verify the package.
- [ ] **Step 5:** Add `db:types:check` to regenerate into a temp file and byte-diff the committed type file after a clean local reset.
- [ ] **Step 6:** Commit generated database contracts.

## Chunk 3: Auth and endpoint safety

### Task 7: Create typed environment and Supabase client factories

**Files:**

- Create: `packages/env/package.json`
- Create: `packages/env/tsconfig.json`
- Create: `packages/env/src/public.ts`
- Create: `packages/env/src/server.ts`
- Create: `packages/env/src/no-root-export.test-d.ts`
- Test: `packages/env/src/public.test.ts`
- Test: `packages/env/src/server.test.ts`
- Create: `packages/supabase/package.json`
- Create: `packages/supabase/tsconfig.json`
- Create: `packages/supabase/src/browser.ts`
- Create: `packages/supabase/src/types.ts`
- Test: `packages/supabase/src/browser.test.ts`

- [ ] **Step 1:** Write failing tests for missing/malformed URLs, publishable-key format, and server secret rejection from public config.
- [ ] **Step 2:** Implement exact package subpath exports `@workspace/env/public` and `@workspace/env/server` with no root barrel. Add `server-only` to the server entry and prove a Vite fixture cannot bundle it.
- [ ] **Step 3:** Write a failing test for a typed browser client factory.
- [ ] **Step 4:** Implement the browser factory using `@supabase/supabase-js`, a publishable key, generated `Database` types, and injected configuration.
- [ ] **Step 5:** Run tests, lint, and typecheck until green.
- [ ] **Step 6:** Prohibit both legacy `service_role` and current `sb_secret_` values outside a future isolated server-only module; secret clients must never share cookies or request Authorization headers.
- [ ] **Step 7:** Commit environment and browser data boundaries.

### Task 8: Create framework-neutral secure endpoint primitives

**Files:**

- Create: `packages/api/package.json`
- Create: `packages/api/tsconfig.json`
- Create: `packages/api/src/errors.ts`
- Create: `packages/api/src/json.ts`
- Create: `packages/api/src/authenticate.ts`
- Create: `packages/api/src/authorize.ts`
- Create: `packages/api/src/rate-limit.ts`
- Create: `packages/api/src/audit.ts`
- Create: `packages/api/src/define-authenticated-route.ts`
- Create: `packages/api/src/define-public-route.ts`
- Create: `packages/api/src/define-authenticated-action.ts`
- Create: `packages/api/src/index.ts`
- Test: `packages/api/src/define-authenticated-route.test.ts`
- Test: `packages/api/src/define-public-route.test.ts`
- Test: `packages/api/src/define-authenticated-action.test.ts`

- [ ] **Step 1:** Write one failing test per behavior for 401 unauthenticated, 403 unauthorized, 400 invalid JSON, 422 invalid input, absent scoped client, absent executable limiter, 429 limiter denial, absent audit sink, audit failure before handler, redacted 500 errors, DTO output, and successful typed execution. Run `pnpm --filter @workspace/api test -- --run` after each RED/GREEN increment.
- [ ] **Step 2:** Implement and export the exact checked names `defineAuthenticatedRoute`, `definePublicRoute`, and `defineAuthenticatedAction` over small shared internals using dependency injection and Zod schemas.
- [ ] **Step 3:** Ensure authentication and resource authorization run inside every invocation, never only in UI/proxy checks.
- [ ] **Step 4:** Require an executable async rate-limiter dependency plus a named policy. A denied decision returns 429 with `Retry-After`; production construction fails if only the development in-memory limiter is present. Exemptions are allowed only through the reviewed public-entrypoint manifest.
- [ ] **Step 5:** Require an async structured audit sink with redaction. Failure before handler execution returns 503 and fails closed; authorization/rate-limit denials and handler outcomes emit request ID, actor ID, action, resource ID, decision, and safe error code without tokens or payloads.
- [ ] **Step 6:** Add `Cache-Control: private, no-store`, a request ID, safe JSON content type, and audit outcomes for allow/deny/error paths.
- [ ] **Step 7:** Implement the equivalent Server Action wrapper: validate input, verify identity, authorize resource, inject user-scoped DAL/client, execute limiter, emit audit event, and return DTO-safe results.
- [ ] **Step 8:** Run focused and workspace tests until green.
- [ ] **Step 9:** Commit endpoint security primitives.

### Task 9: Add Next.js auth and secure entrypoint adapters

**Files:**

- Modify: `apps/admin/package.json`
- Create: `apps/admin/lib/supabase/client.ts`
- Create: `apps/admin/lib/supabase/server.ts`
- Create: `apps/admin/lib/supabase/proxy.ts`
- Create: `apps/admin/lib/auth/identity.ts`
- Create: `apps/admin/lib/actions/secure-action.ts`
- Create: `apps/admin/proxy.ts`
- Test: `apps/admin/lib/auth/identity.test.ts`
- Test: `apps/admin/lib/supabase/proxy.test.ts`
- Modify: `apps/api/package.json`
- Create: `apps/api/lib/supabase/request-client.ts`
- Create: `apps/api/lib/auth/verify-bearer.ts`
- Create: `apps/api/lib/http/secure-route.ts`
- Create: `apps/api/lib/http/cors.ts`
- Create: `apps/api/lib/rate-limit/runtime-limiter.ts`
- Create: `apps/api/lib/audit/vercel-audit.ts`
- Test: `apps/api/lib/auth/verify-bearer.test.ts`
- Test: `apps/api/lib/http/secure-route.test.ts`
- Test: `apps/api/lib/http/cors.test.ts`
- Test: `apps/api/lib/rate-limit/runtime-limiter.test.ts`
- Test: `apps/api/lib/audit/vercel-audit.test.ts`
- Create: `apps/api/app/api/security-contract/route.ts`
- Test: `apps/api/app/api/security-contract/route.test.ts`

- [ ] **Step 1:** Read local Next 16 authentication, data-security, cookies, and proxy guides before code.
- [ ] **Step 2:** Write failing tests proving `getSession()` is never accepted for server authorization, invalid/expired claims are rejected, only verified `sub` becomes identity, and tenant roles never come from JWT metadata.
- [ ] **Step 3:** Add pinned `@supabase/ssr` and `@supabase/supabase-js` dependencies.
- [ ] **Step 4:** Implement admin browser/server clients with async `cookies()` and the current `getAll`/`setAll` contract. The browser wrapper must reuse `@workspace/supabase/browser`.
- [ ] **Step 5:** Implement admin session refresh using `getClaims()`. Propagate every refreshed cookie and the SSR-provided cache headers on normal and redirect responses; test matcher exclusions and failure paths. Proxy remains optimistic, never the authorization boundary.
- [ ] **Step 6:** Implement API bearer verification with `getClaims(token)` and create a user-scoped Supabase client carrying only the verified bearer token plus publishable key. RLS/membership rows remain authoritative.
- [ ] **Step 7:** Write RED/GREEN tests for exact-origin CORS: allowed admin/caja origins, denied unknown/null origins, OPTIONS preflight, allowed methods/headers, credentials policy, and `Vary: Origin`. Wildcard origins are forbidden.
- [ ] **Step 8:** Implement production adapter factories for an executable limiter and structured Vercel audit logger. The in-memory limiter is development/test only and production startup fails without an externally enforced Vercel rate-limit policy recorded in readiness evidence.
- [ ] **Step 9:** Make app-local adapters thin configuration factories that return the exact shared wrappers; they must not introduce alternate names recognized by the checker.
- [ ] **Step 10:** Add a fixture Route Handler through `defineAuthenticatedRoute`. Integration tests must prove the handler body cannot run when authentication, authorization, validation, scoped-client, limiter, audit, or CORS setup fails.
- [ ] **Step 11:** Keep secret/admin clients out until a separately approved concrete use case exists. For sensitive future operations document short token lifetime and session revocation checks.
- [ ] **Step 12:** Run `pnpm --filter admin test -- --run`, `pnpm --filter api test -- --run`, `pnpm security`, lint, typecheck, and both Next production builds.
- [ ] **Step 13:** Commit auth and secure entrypoint adapters.

## Chunk 4: Cloud delivery and production gates

### Task 10: Add Vercel-safe configuration and headers

**Files:**

- Create: `apps/admin/lib/security/csp.ts`
- Modify: `apps/admin/proxy.ts`
- Test: `apps/admin/lib/security/csp.test.ts`
- Create: `apps/api/lib/security/headers.ts`
- Test: `apps/api/lib/security/headers.test.ts`
- Create: `apps/caja/vercel.json`
- Modify: `apps/caja/vite.config.ts`
- Create: `apps/caja/src/security/csp.ts`
- Test: `apps/caja/src/security/csp.test.ts`
- Modify: `apps/web/next.config.ts`
- Create: `apps/web/lib/security/headers.ts`
- Test: `apps/web/lib/security/headers.test.ts`
- Create: `docs/VERCEL.md`
- Create: `docs/PRODUCTION_READINESS.md`

- [ ] **Step 1:** Write failing tests for a strict nonce CSP in the authenticated admin, HSTS in production, no-sniff, frame denial, strict referrer policy, permissions policy, and `private, no-store` on authenticated responses.
- [ ] **Step 2:** Merge nonce generation with the admin session proxy, forward the nonce to Next, propagate Supabase cookies/cache headers, include exact Supabase/API `connect-src` origins, and require dynamic rendering for protected admin routes. Do not add `unsafe-inline` or a misleading static CSP.
- [ ] **Step 3:** Add API hardening headers. Generate caja's static CSP during Vite HTML transformation from validated exact `VITE_SUPABASE_URL` and `VITE_API_URL` origins; fail production builds when either is absent or wildcard. Allow no inline scripts.
- [ ] **Step 4:** Add public web baseline headers (HSTS in production, no-sniff, frame denial, referrer and permissions policy). Use Next 16's documented strict nonce CSP only if accepting dynamic rendering; otherwise leave CSP as an explicit production-readiness blocker rather than shipping `unsafe-inline` or claiming strict protection.
- [ ] **Step 5:** Document four independent Vercel projects, root/build/output directories, local/preview/production environment separation, redirect URLs, preview protection, secret scopes, and production promotion.
- [ ] **Step 6:** Document Supabase local → non-production → production topology, migration promotion, drift checks, backup/restore rehearsal, and the rule that Vercel previews must never use production Supabase credentials.
- [ ] **Step 7:** Add a production-readiness blocker requiring evidence of GitHub rulesets, required checks, Vercel production branch/protection, scoped secrets, Supabase backups, SMTP, Auth redirect allowlist, rate limits, exact CSP origins, and rollback ownership before first production promotion.
- [ ] **Step 8:** Run `next build && next start` for admin/web and verify real response headers with HTTP requests; verify Vite output contains no inline scripts forbidden by its CSP.
- [ ] **Step 9:** Commit deployment hardening.

### Task 11: Enforce CI security gates

**Files:**

- Create: `.github/workflows/quality.yml`
- Create: `.github/workflows/database.yml`
- Create: `.github/dependabot.yml`
- Create: `docs/PULL_REQUEST_CHECKLIST.md`
- Create: `.github/actionlint.yaml`

- [ ] **Step 1:** Add CI jobs for frozen install, non-mutating formatting check, zero-error/zero-new-warning lint, typecheck, unit tests, architecture/entrypoint/secret checks, dependency audit, and all builds on exact Node 24.18.0.
- [ ] **Step 2:** Add a Supabase job that starts the local stack and runs migrations plus pgTAP tests.
- [ ] **Step 3:** After reset/tests, regenerate database types to a temp file and fail on drift.
- [ ] **Step 4:** Pin every GitHub Action to an immutable full SHA with a version comment. Set top-level `permissions: contents: read`; no `pull_request_target`, self-hosted runner, write token, untrusted event interpolation, or secret echo.
- [ ] **Step 5:** Run `actionlint` and a workflow security scanner; fail on unpinned actions/images or unsafe workflow constructs.
- [ ] **Step 6:** Run a redacting secret scanner (including Supabase legacy/current keys, database URLs, Vercel tokens, P12/PEM material) and `pnpm audit --audit-level high` as release gates.
- [ ] **Step 7:** Add dependency update policy with grouped, reviewed updates.
- [ ] **Step 8:** Add a PR checklist covering tenancy, authn/authz, validation, secrets, logs, rate limiting, idempotency, tests, generated types, migration rollback, and external production-readiness evidence.
- [ ] **Step 9:** Validate workflow syntax and run all local equivalents.
- [ ] **Step 10:** Commit CI and review gates.

## Chunk 5: Completion audit

### Task 12: Verify the full foundation

**Files:**

- Modify only files required to fix verification findings

- [ ] **Step 1:** Run `pnpm format:check`, `pnpm lint`, `pnpm typecheck`, `pnpm test`, `pnpm security`, `pnpm audit --audit-level high`, and `pnpm build`.
- [ ] **Step 2:** Start local Supabase, reset the database, and run all pgTAP tests from a clean state.
- [ ] **Step 3:** Run the automated searches for leaked secret keys, unguarded HTTP/Server Action entrypoints, direct database URLs, unsafe metadata authorization, missing RLS, workflow hazards, and source files above the documented limit.
- [ ] **Step 4:** Review every explicit objective against authoritative files and command output.
- [ ] **Step 5:** Dispatch a final security/schema/code review and fix every material issue.
- [ ] **Step 6:** Confirm the worktree is clean except for intended changes and present the branch for user review.
