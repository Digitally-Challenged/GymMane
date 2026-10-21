# GymMane sync backend

Node 22+, PostgreSQL 14+, TypeScript. Implements `../docs/sync-contract.md` v1. No production connections or deployment are required for tests. Anonymous/offline app use is independent of this service.

## Local startup

From `backend/`, run `npm ci`, copy `.env.example` to `.env`, and replace placeholders with your **local** database and auth-provider configuration. Create an empty database with a dedicated owner, then:

```sh
node --env-file=.env --import tsx src/migrate.ts
npm run build
node --env-file=.env dist/src/main.js
```

The HTTP listener defaults to loopback. Set `CORS_ALLOWED_ORIGINS` to comma-separated exact web origins (no wildcard); unauthenticated OPTIONS preflight checks the registered method and allowed headers, while actual requests still require authentication. Empty configuration rejects cross-origin browser requests. Deployment requires an HTTPS reverse proxy, network-level request/rate quotas, database TLS with certificate verification, and a private database reachable only by the backend. Do not expose this database to Supabase client roles: no client-side database access or RLS policy is supplied. Do not use a Supabase service-role token as an end-user credential. No secrets are compiled into the server. Configure issuer, audience, and asymmetric JWKS URL; only ES256/RS256 are accepted. Legacy shared-secret HS256 projects must migrate signing keys.

For a container, run `docker build -t gymmane-sync .`, run migrations as a release step using `node dist/src/migrate.js`, then start the container with environment variables. The container listens on 8080 as a non-root user. No infrastructure is provisioned by these files.

## Protocol and persistence

`POST /v1/sync/push` and `GET /v1/sync/pull?cursor=0&limit=100` require `Authorization: Bearer <JWT>`. Responses match contract v1; errors have `{error: string}`. The verified UUID subject is the only account identity. UUID text is normalized lowercase. JSON bodies are limited to 1 MiB, individual payloads to 64 KiB, operations and pull pages to 100. Known legacy workout/routine fields are validated; additional fields are preserved, so callers must never send credentials or whole-app state. Payload `id` must match envelope `entityId`.

Workout `d` uses the shared ISO-style grammar `YYYY-MM-DDTHH:mm:ss[.ffffff][Z]`, with one to six fractional digits when present; Dart's negative four-digit and signed six-digit years are also supported within the shared DateTime range. Calendar days (including leap years) and clock fields must be real values: prose dates, date-only strings, overflow dates/times, timezone offsets and trailing text are rejected before any changes are written. New workouts must be serialized in UTC by storage (`Z`); timezone-less legacy `DateTime.toIso8601String()` values remain accepted because the v1 envelope cannot distinguish adopted legacy workouts from newly created ones. The server preserves timestamp text and microseconds without assigning a timezone to legacy values. `tests/fixtures/workout-dates.json` is exercised through HTTP push/pull and parsed with real Dart by `dart tests/date_compatibility.dart` (run from `backend/`).

An account row lock serializes pushes. Entity, immutable change entry, cursor allocation and operation receipt commit in one transaction; an entire push batch is atomic. Every replay returns its original accepted/conflict result, even after newer writes. Different content for an existing operation ID returns 409 and rolls back the batch. Conflict receipts preserve the submitted operation in the database; clients must also retain their pending edit. Missing entities with a nonzero base revision return 400 because the v1 response cannot encode a nonexistent current entity. A zero-base deletion creates a tombstone. Tombstones, changes and receipts have no expiry in v1.

Cursors are decimal strings scoped to the authenticated account and only meaningful within that account. Never reuse a cursor across accounts. Account serialization prevents sequence allocation/commit races; pull reads immutable committed entries and fetches one extra row to determine `hasMore`. A cursor ahead of the current account returns an empty page preserving that cursor. Revision overflow is rejected. No device timestamp determines ordering.

JWT signatures, issuer, audience, expiry, subject and issue time are verified on every request. JWKS retrieval uses jose's bounded cache. Provider sign-out/revocation does **not** invalidate already-issued JWTs immediately: they remain usable until expiry unless an administrator sets `sync_accounts.tokens_valid_after` to the revocation epoch second (tokens issued at or before that second are rejected), or `disabled=true` to forbid the account. These controls have no public administrative endpoint; a provider revocation webhook/introspection integration remains a deployment decision. An already authorized in-flight request may complete. JWKS rotation and live Supabase interoperability require a configured staging provider test.

400 invalid; 401 missing/invalid/expired/revoked token; 403 disabled account; 409 operation ID misuse or exhausted revision; 413 input limits; 503 transient/internal failure. Edge quotas should return 429. The runtime does not itself implement distributed rate limiting or storage quotas. Database errors do not expose payloads or connection strings.

## Module boundary

`src/modules.ts` exports `BackendModule(registry, {pool})`. Pass modules to `createApp(pool, auth, modules)`; no Strava module is implicitly enabled. `STRAVA_ENABLED=true` loads `strava/index.js` and calls `createStravaModule(pool, process.env)`; missing modules fail startup. Registered module jobs tick every five seconds without overlap and shutdown waits for an active tick before closing the database. Provider operations must have bounded network timeouts. `registry.authenticated(method, path, handler)` receives `{accountId, request, url, readJson}` and returns JSON. `readJson` enforces the common byte limit.

OAuth modules can deliberately register `registry.publicCallback(method, path, verifyState, handler)`. `verifyState(request, url)` must validate and atomically consume one-use OAuth state and return its bound account ID before the handler runs. This route does not require app bearer auth. Handlers throw `HttpError(status, safeMessage)` for public errors. Route names must be unique. Module owners manage their own transactions, encryption, jobs and shutdown integration; migrations are numbered SQL files under `migrations/` and run transactionally with an advisory lock. Strava owns migration 002 and `strava/`; shared startup registration remains an explicit integration step.

## Verification

```sh
npm run check
npm run format:check
npm run build
npm test                        # unit tests; SQL tests explicitly skip without TEST_DATABASE_URL
bash scripts/test-postgres.sh   # starts disposable loopback Postgres; runs all tests; stops/removes it
dart tests/date_compatibility.dart # optional Dart SDK: shared timestamp fixtures
bash scripts/test-postgres.sh node --import tsx tests/flutter_sync_harness.ts # requires Flutter SDK
```

The integration runner requires local PostgreSQL binaries, uses trust auth only on its disposable loopback cluster, and defaults to port 55440 (`TEST_POSTGRES_PORT` overrides). Alternatively set `TEST_DATABASE_URL` to an isolated localhost database whose name ends `_test`; tests migrate it and intentionally inject a receipt failure trigger. Never point tests at a shared database. Tests execute actual SQL and sign ES256 JWTs against a real local HTTP JWKS endpoint. They cover auth rejection/revocation, account isolation, operation misuse, original conflict receipts, tombstones, pagination, concurrency, receipt failure rollback and HTTP-server restart durability. They do not prove device sync, production recovery, live-provider auth or cloud deployment.

The Flutter harness starts the production Node HTTP app plus a loopback JWKS server and launches `flutter test test/sync/live_backend_test.dart`. It generates ES256 signing keys in memory and passes short-lived test JWTs only through the child environment. Two independent SQLite-backed `SyncRepository` instances use the real `SyncTransport` to prove offline edits in both reconnect orders, preservation and explicit resolution of routine/workout conflicts, accepted/conflict receipt replay, account isolation with identical entity IDs, and tombstones surviving repository restart. The test explicitly skips outside this harness. This exercises repository/transport integration, not the UI/controller lifecycle, physical devices, or live identity providers; all records are synthetic and the disposable database is removed on exit.

Back up all sync tables and the migration ledger together using PostgreSQL backup tooling; restore to an isolated database before switching traffic. Do not independently restore/truncate receipts or changes, which would break retries and cursors. Production backup/restore drills and retention/storage capacity planning remain release requirements.

API references checked during implementation: [jose JWT verification](https://github.com/panva/jose/blob/main/docs/jwt/verify/functions/jwtVerify.md), [node-postgres transactions](https://node-postgres.com/features/transactions), [Supabase JWTs](https://supabase.com/docs/guides/auth/jwts).
