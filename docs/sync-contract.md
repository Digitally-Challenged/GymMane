# Native sync contract v1

Implementation baseline: `239842e4e8e02218b03d96ee05af579435a1b9ce` (includes the catalog, art and prescribed training programs). This is an additive opt-in feature; anonymous/offline use remains available. Server deployment is configured separately.

## Ownership

Storage owns local persistence, model identities, backup validation and state persistence wiring. Apple owns `ios/` and dedicated HealthKit Dart adapter. Backend owns `backend/` including authentication and provider delivery. Coordinator owns this contract, final app connection/status UI and integration. No worker edits another owner's paths without a coordinator message. Storage owns pubspec dependency additions in the first wave; other workers request additions.

## Remote protocol

Use authenticated HTTPS JSON. Default server implementation targets Postgres and verifies Supabase-compatible JWTs by issuer/audience/JWKS; auth provider config is environment supplied, not compiled credentials. Never trust a caller-supplied account ID. Derive it from a verified token. Clients authenticate using a provider adapter; no credentials go in exported workouts/backups.

`POST /v1/sync/push`: body `{schemaVersion:1, operations:[{operationId,entityType,entityId,baseRevision,deleted,payload}]}`. UUID operation/entity IDs; entityType is `workout` or `routine`; baseRevision nonnegative integer (zero creates); deleted boolean, payload object or null for deletion. Max 100 operations and bounded payload sizes. Server returns `{results:[{operationId,status,entity}]}` with status `accepted` or `conflict`. Entity is `{entityType,entityId,revision,deleted,payload,cursor}`. Cursor is an opaque decimal string; revisions are positive safe integers. Idempotent replay of the same operation returns original result; reuse with different content rejects. Each operation and corresponding receipt commit atomically. Conflict returns current entity and does not discard the local pending revision. Exact error status contract: 400 invalid, 401 unauthenticated, 403 forbidden, 409 operation-ID misuse, 413 size limit, 429 quota, 5xx retriable.

`GET /v1/sync/pull?cursor=0&limit=100`: returns `{entities:[...],nextCursor,hasMore}`. Account-scoped monotonic change log, immutable entries or equivalent race-safe ordered retrieval. Tombstones retained in v1. Pull cursor is committed atomically with local application. Ignore device wall clocks for ordering. No whole-app-state replication.

Completed workout payload contains existing logged-session JSON plus stable `id`; routine payload preserves existing routine JSON plus stable UUID identity where migrated. Payload schemas are validated on both sides without removing supported legacy fields. Original exercise catalog IDs remain unchanged. Detailed storage migration is responsible for preserving identities across repeated import/backup/restore. No active session, secrets, photos, nutrition, or device preferences are synced.

Newly recorded workouts preserve nullable `startedAt` as the actual UTC start, `d` as finish time, `dur` as active seconds, and `utcOffsetSeconds` as the recorded local offset. Pauses increase elapsed time without increasing active time. Old records without a trustworthy start remain synchronizable but are unsupported for automatic provider export; never reconstruct start by subtracting active duration from finish. Supplied times must be valid and ordered, with active duration no more than elapsed plus one second of timer rounding. Strava receives actual start, elapsed seconds and active seconds separately.

## Local reliability

Local data commit and outgoing change commit are atomic. Serialize persistence writes and await critical workout/restore completion. Failed or corrupt reads cannot silently overwrite original data with empty state. Preserve the legacy preferences document and media until migration has committed and been validated. Stage and validate backup content before replacing any local data.

Keep account namespaces isolated. Guest adoption is explicit; do not upload all historic workouts without confirmation. A same-entity edit conflict is preserved for resolution, never last-write-wins by timestamp. Imported remote writes do not enqueue echo operations. A completed workout continued for editing retains identity. Deleting creates a tombstone, not removal of identity/history needed for reconciliation.

## External delivery

HealthKit MethodChannel `gymmane/healthkit`: `availability`, `authorization`, `requestAuthorization`, `saveWorkout`, `deleteWorkout`. Adapter specifies exact return shapes in its public Dart interface. `saveWorkout` input: `{id,revision,startTime,endTime,durationSeconds,name}` using UTC ISO times and seconds. Native writes traditional strength workout plus namespaced sync identifier/version; never fabricated energy/heart data. Reject invalid times/IDs. Unsupported and permission failures are explicit. HealthKit does not run in web. Device export ownership and ledger handled by app integration.

Strava is server-side OAuth and queued upload. Store secrets/tokens encrypted, serialize rotating refresh, and fence account/connection generations. Server ledger keyed by account + workout UUID; statuses queued, sending, processing, confirmed, unknown, needsAuthorization, failed, unsupported. Unknown accepted-upload outcomes require reconciliation, not blind retries. No full remote set-edit/delete promises. Export only GymMane-origin records with explicit destination opt-in. Manual FIT export remains separate.

## Verification

Test account isolation, idempotency/misuse, conflicting edits and tombstones, cursor pagination/restart, interrupted commits, invalid backups, token revocation, upload response loss and physical-device HealthKit permission behavior. Missing live credentials may block live verification, but not implementation or deterministic local tests. Do not claim a mock proves live interoperability.

## Building and configuring the native trial

The Apple host uses bundle ID `com.gymmane.app` and supports iPhone and iPad. Simulator verification does not constitute a signed device build or TestFlight release. Select the intended Apple Developer team and register that bundle ID with HealthKit before signing; verify entitlements on physical devices.

With the pinned Flutter SDK on PATH, generate native configuration with `FLUTTER_SWIFT_PACKAGE_MANAGER=true flutter build ios --simulator --no-codesign --config-only`, then run `pod install` from `ios/`. An arm64 simulator build can be produced from the repository root with:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Account sync requires an existing email/password account at the configured auth provider, the deployed backend, and these public Flutter build definitions: `GYMMANE_SYNC_URL` (HTTPS backend origin), `GYMMANE_AUTH_URL` (HTTPS Supabase project origin), `GYMMANE_AUTH_PUBLIC_KEY` (public anon/publishable key), and `GYMMANE_EMAIL_AUTH=true`. Never put a service-role key, database password, Strava secret, or encryption key in Flutter definitions. A build without this configuration remains usable offline and reports cloud sync as unavailable. Configure the backend separately using `backend/README.md` and Strava using `backend/strava/README.md`.

Apple Health exports are explicit, per-workout actions from the iPhone the user chooses. The designation is device-local; it is not an enforced account-wide lease. Use one phone, synchronize iPad workouts to it, then export there. Do not assume background delivery or safely re-export all history after reinstall/replacement. Strava's independent Send to Health behavior can create another copy; review that routing before exporting to both services. Deleting local history does not retract an existing provider copy automatically.

Current release gates include real auth-provider interoperability, physical iPhone/iPad convergence, HealthKit permission/revision/deletion behavior, live Strava OAuth/upload/retry verification, and signed TestFlight delivery. Local fake-provider and simulator checks must be reported separately from those gates.
