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

For containers, use the isolated release procedure below. The container listens on 8080 as a non-root user. No infrastructure is provisioned by these files.

## Synology / Docker Compose deployment

This is an operator-run procedure; packaging, syntax checks and verification never deploy. Use Docker Engine with Compose v2.20+ on a supported Synology Container Manager host (or standard Linux Docker host), Python 3.9+, and sufficient disk/RAM for Node 22 and PostgreSQL 16. Reserve the **new** project `gymmane-prod`, its private networks and its named `postgres-data` volume. The project has no external networks, host mounts, fixed container names or published database port. Do not reuse openGym's project, containers, networks, credentials, directories or volumes. Inspect existing host resources before starting anything; never run `down -v`, prune, or remove volumes during a release.

The API is nonroot with a read-only filesystem, dropped capabilities and bounded resources. PostgreSQL has a durable project-scoped volume on an internal Docker network; API egress is separate for HTTPS JWKS/provider requests. API startup depends on healthy PostgreSQL and successful transactional migrations from the **same release image**. [Compose's dependency conditions](https://docs.docker.com/compose/how-tos/startup-order/) implement these gates. Only API port `127.0.0.1:18080` is published by default. This assumes an HTTPS reverse proxy on the **same host**; a proxy on another host needs a separately reviewed private-network/firewall change.

Provide public DNS, a valid TLS certificate and an HTTPS reverse proxy to the loopback port before exposing sync. Apply edge request/rate quotas and preserve `Authorization`, request methods and paths. Do not add bearer authentication to `/health`; it discloses only readiness and the configured release SHA. Private same-host Docker traffic uses the isolated bridge; it is not database TLS. An external database requires verified TLS and a separately reviewed connection/network configuration. Keep the database unreachable from public networks and Supabase client roles.

From the **final integrated, clean committed repository**, package the explicitly chosen commit. A named ref or full SHA must resolve to the current HEAD. The packager rejects dirty/untracked files, old/missing refs, private/generated files, missing migration `003*.sql`, and missing `exerciseDefinitions` in the protocol. It archives committed `backend/` and `scripts/release/` including every migration and the final custom definition code, plus a `RELEASE` file; it never packages an earlier worker snapshot or local `.env`. Output must be a new path outside the checkout:

```sh
python3 scripts/release/package.py HEAD /tmp/gymmane-release.tar.gz
```

Transfer that artifact through the approved private channel, verify its checksum, and extract into a new GymMane-only release directory on the host. Set `GYMMANE_RELEASE` from the bundle's `RELEASE` file. A packaging success proves source identity, not a running release or a published remote ref. Build on the host for its architecture; review and record the resolved Node/PostgreSQL image digests for each release. The base-image tags receive security updates, so identical source archives do not promise identical base-image bytes.

Supply variables **at runtime** through the deployment process/secret manager. Never commit/write credentials into the bundle, Docker build args, shell arguments/history, Flutter defines, logs, database backups, or a project `.env`. All commands below disable implicit `.env` loading; do not print `env`, `docker inspect`, or resolved `compose config` output. Docker host administrators can read container environments; restrict Docker/NAS administrative access.

- Required: `GYMMANE_RELEASE` (40-character lowercase commit SHA), `GYMMANE_DB_USER`, `GYMMANE_DB_NAME`, `GYMMANE_DB_PASSWORD`, `AUTH_ISSUER`, `AUTH_AUDIENCE`, `AUTH_JWKS_URL`.
- Database user/name: lowercase letter followed by up to 39 lowercase letters, digits or underscores. Reserve `gymmane_restore_` names for restore drills. Generate a unique password of 32–128 URL-safe letters, digits, `_` or `-` in the secret manager. This allows safe assembly of `DATABASE_URL` without URL escaping; never reuse another application's password. PostgreSQL initialization variables apply only to a new volume; later rotation requires explicit database-side password changes.
- Auth: issuer and asymmetric JWKS URL must use HTTPS; configure the real provider's audience. Local auth exceptions are disabled. `CORS_ALLOWED_ORIGINS` optionally lists exact HTTPS web origins; empty continues to reject browser cross-origin requests.
- Optional: `GYMMANE_HTTP_PORT` (unprivileged loopback port, default 18080). `STRAVA_ENABLED` defaults to `false`; enable only with all four server-only Strava variables described in `strava/README.md`, the approved HTTPS callback and verified live provider setup. Preserve `STRAVA_TOKEN_KEY` separately in the secret manager across releases/restores; it is never part of a database backup.

With variables already injected into the operator process, run these from the extracted bundle root. Validation captures and suppresses all resolved configuration/error output. These commands target only `gymmane-prod`; successful migration is required before the API starts. For upgrades, first back up the database, then stop the old API during migrations to avoid concurrent old-version writes:

```sh
python3 scripts/release/check_compose.py
docker compose --env-file /dev/null --project-name gymmane-prod -f backend/deploy/compose.yaml build api migrate
# Upgrade only: back up first using the procedure below, then:
docker compose --env-file /dev/null --project-name gymmane-prod -f backend/deploy/compose.yaml stop api
docker compose --env-file /dev/null --project-name gymmane-prod -f backend/deploy/compose.yaml up -d --wait --wait-timeout 180
python3 scripts/release/verify.py https://YOUR_BACKEND_ORIGIN "$GYMMANE_RELEASE"
```

`GET /health` returns HTTP 200 with exactly `{"status":"ok","release":"<configured SHA>"}` after a database migration-ledger readiness query; database failure or an uninitialized ledger returns HTTP 503 with exactly `{"status":"unavailable","release":"<configured SHA>"}`. Other methods do not expose a public health handler. Requests have `Cache-Control: no-store`. `createApp(pool, auth, modules, {release, allowedOrigins})` injects release identity for tests. Local development may omit it and reports `development`; Compose requires a SHA. Startup/migration failures emit generic messages without provider/connection details. Other API authentication and CORS checks are unchanged.

The verifier uses a bounded, certificate-verified HTTPS GET with no credentials or redirects. It rejects non-200 status, wrong release, unexpected fields and unavailable state, without printing response bodies. A public 200 alone is insufficient. Match the expected SHA to the bundle, built image and independently verified personal-fork release ref; the configured SHA is not a cryptographic attestation. After health, perform real authenticated two-device sync and approved provider smoke tests. Health does not prove auth-provider interoperability, account isolation on live devices, TLS proxy correctness for every route, or Strava readiness.

### Non-destructive backup and restore drill

Before upgrades, take a whole-database custom-format snapshot from the existing isolated GymMane database. Do not migrate while taking the snapshot. The script uses only the fixed `gymmane-prod` project's `db` service, writes an exclusive mode-0600 file, never overwrites a backup, and removes a newly created partial file on failure. Store backups outside source/release directories; encrypt them in approved backup storage and retain an off-host copy. Dumps contain private sync data and encrypted provider tokens, so treat them as sensitive. Runtime plaintext secrets and `STRAVA_TOKEN_KEY` remain in the secret manager; never put them in the dump or its metadata.

```sh
python3 scripts/release/database.py backup /PRIVATE_BACKUP_DIRECTORY/gymmane-before-upgrade.dump
python3 scripts/release/database.py restore-drill /PRIVATE_BACKUP_DIRECTORY/gymmane-before-upgrade.dump gymmane_restore_oct21
```

Restore creates a **new** `gymmane_restore_<drill>` database and fails if that database exists. It never drops, cleans, overwrites or points traffic at the live database; failed drills remain isolated for inspection. The whole database includes sync entities, change cursors, operation/conflict receipts, Strava ledgers and `backend_migrations`. Never restore these tables independently. Verify restored migrations/counts, replay/cursor behavior and an isolated test API before any recovery switch. A production recovery needs a separately approved empty target/volume and traffic switch; this script deliberately does not perform that switch. Application rollback after schema changes requires compatibility review or an independently verified full recovery; changing the image tag alone cannot undo migrations. Backup retention, encryption, available NAS storage, restore verification and the final production cutover remain operator prerequisites.

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
