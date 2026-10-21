# Native sync contract v1

Implementation baseline: `239842e4e8e02218b03d96ee05af579435a1b9ce` (includes the catalog, art and prescribed training programs). This is an additive opt-in feature; anonymous/offline use remains available. Server deployment is configured separately.

## Ownership

Storage owns local persistence, model identities, backup validation and state persistence wiring. Apple owns `ios/` and dedicated HealthKit Dart adapter. Backend owns `backend/` including authentication and provider delivery. Coordinator owns this contract, final app connection/status UI and integration. No worker edits another owner's paths without a coordinator message. Storage owns pubspec dependency additions in the first wave; other workers request additions.

## Remote protocol

Use authenticated HTTPS JSON. Default server implementation targets Postgres and verifies Supabase-compatible JWTs by issuer/audience/JWKS; auth provider config is environment supplied, not compiled credentials. Never trust a caller-supplied account ID. Derive it from a verified token. Clients authenticate using a provider adapter; no credentials go in exported workouts/backups.

`POST /v1/sync/push`: body `{schemaVersion:1, operations:[{operationId,entityType,entityId,baseRevision,deleted,payload}]}`. UUID operation/entity IDs; entityType is `workout` or `routine`; baseRevision nonnegative integer (zero creates); deleted boolean, payload object or null for deletion. Max 100 operations and bounded payload sizes. Server returns `{results:[{operationId,status,entity}]}` with status `accepted` or `conflict`. Entity is `{entityType,entityId,revision,deleted,payload,cursor}`. Cursor is an opaque decimal string; revisions are positive safe integers. Idempotent replay of the same operation returns original result; reuse with different content rejects. Each operation and corresponding receipt commit atomically. Conflict returns current entity and does not discard the local pending revision. Exact error status contract: 400 invalid, 401 unauthenticated, 403 forbidden, 409 operation-ID misuse, 413 size limit, 429 quota, 5xx retriable.

`GET /v1/sync/pull?cursor=0&limit=100`: returns `{entities:[...],nextCursor,hasMore}`. Account-scoped monotonic change log, immutable entries or equivalent race-safe ordered retrieval. Tombstones retained in v1. Pull cursor is committed atomically with local application. Ignore device wall clocks for ordering. No whole-app-state replication.

Completed workout payload contains existing logged-session JSON plus stable `id`; routine payload preserves existing routine JSON plus stable UUID identity where migrated. Payload schemas are validated on both sides without removing supported legacy fields. Original exercise catalog IDs remain unchanged. Detailed storage migration is responsible for preserving identities across repeated import/backup/restore. No active session, secrets, photos, nutrition, or device preferences are synced.

## Local reliability

Local data commit and outgoing change commit are atomic. Serialize persistence writes and await critical workout/restore completion. Failed or corrupt reads cannot silently overwrite original data with empty state. Preserve the legacy preferences document and media until migration has committed and been validated. Stage and validate backup content before replacing any local data.

Keep account namespaces isolated. Guest adoption is explicit; do not upload all historic workouts without confirmation. A same-entity edit conflict is preserved for resolution, never last-write-wins by timestamp. Imported remote writes do not enqueue echo operations. A completed workout continued for editing retains identity. Deleting creates a tombstone, not removal of identity/history needed for reconciliation.

## External delivery

HealthKit MethodChannel `gymmane/healthkit`: `availability`, `authorization`, `requestAuthorization`, `saveWorkout`, `deleteWorkout`. Adapter specifies exact return shapes in its public Dart interface. `saveWorkout` input: `{id,revision,startTime,endTime,durationSeconds,name}` using UTC ISO times and seconds. Native writes traditional strength workout plus namespaced sync identifier/version; never fabricated energy/heart data. Reject invalid times/IDs. Unsupported and permission failures are explicit. HealthKit does not run in web. Device export ownership and ledger handled by app integration.

Strava is server-side OAuth and queued upload. Store secrets/tokens encrypted, serialize rotating refresh, and fence account/connection generations. Server ledger keyed by account + workout UUID; statuses queued, sending, processing, confirmed, unknown, needsAuthorization, failed, unsupported. Unknown accepted-upload outcomes require reconciliation, not blind retries. No full remote set-edit/delete promises. Export only GymMane-origin records with explicit destination opt-in. Manual FIT export remains separate.

## Verification

Test account isolation, idempotency/misuse, conflicting edits and tombstones, cursor pagination/restart, interrupted commits, invalid backups, token revocation, upload response loss and physical-device HealthKit permission behavior. Missing live credentials may block live verification, but not implementation or deterministic local tests. Do not claim a mock proves live interoperability.
