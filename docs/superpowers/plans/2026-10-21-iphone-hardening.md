# GymMane iPhone Reliability and Usability Implementation Plan

> For agentic workers: use the task and review loop from subagent-driven-development through supervised Orca dispatches. Follow each task's failing-test, implementation, verification, and explicit-file commit steps. Do not spawn nested workers.

**Goal:** Repair all six high/medium review findings and improve the iPhone workout workflow, then publish the verified release to the personal fork and authorized production destination.

**Architecture:** Keep Flutter, transactional local storage, isolated accounts, explicit provider exports, and existing backend. Carry custom exercise dependencies inside routine payloads instead of introducing another replicated entity type. Centralize safe Strava retry eligibility on the server, schedule sync from acknowledged saves and foreground entry, and share one completed-workout delivery component with Settings.

**Tech Stack:** Flutter/Dart, Swift/HealthKit, Node/TypeScript/PostgreSQL, existing Orca runtime.

**Spec:** The October 21 adversarial review and Nick's instruction in this session: iPhone is the primary target; resolve every high/medium finding and ship. Existing baseline is feat-native-sync at 863e6f6, including prior catalog, artwork and strength programs. Existing ios signing edits are intentional and must be preserved except the unnecessary Health capabilities identified in review.

## Global constraints

- iPhone is the primary design and physical validation target. Preserve iPad compatibility; no tablet-specific redesign.
- Preserve offline/guest use, account isolation, existing workout IDs/history/media, and the current artwork/theme.
- Local save success must mean durable commit. Cloud sync and each provider delivery have separate status.
- Never resend a Strava create with an uncertain outcome or an existing upload/activity ID.
- Health exports remain explicit per workout; do not bulk-upload history or invent measurements.
- Secrets stay in secure storage/secret managers, never source, public Flutter defines, logs or backups.
- Push to Digitally-Challenged/GymMane, never the upstream InlitX repository. Verify remote refs and the actual running release.
- All workers are sharing the repository with others. Do not revert another worker's changes, switch another checkout's branch, or edit outside ownership. Ask the coordinator about shared-file changes.
- Use current configured agent model; Orca's version-matched guide overrides stale model examples in generic skills.
- No autonomous deployments by implementation workers. Coordinator owns deployment, credentials and release decisions.

## Review focus

1. A guest routine with one built-in and one custom movement must still start with two movements after adoption and on another device.
2. Known-not-submitted Strava failures must recover without allowing duplicate creation after response loss or reconnect to a different athlete.
3. Persist-and-close must save workout data; resume must synchronize without a long wait or endless sync feedback loop.
4. Workout controls must remain readable and usable at 200% text on a 390x844 iPhone with keyboard, safe areas and effort columns.
5. Export completion must describe the selected workout, never another account's/latest unrelated workout, and preserve explicit consent.

## Wave 0: independent engine and native repairs

### Task D: portable custom exercise dependencies

**Ownership:** lib/models/workout.dart; lib/services/persistence/sync_repository.dart and a focused dependency helper if needed; lib/services/migration/** only as necessary for boundary validation; lib/state/fit_state.dart, library_state.dart, routines_state.dart; backend/src/protocol.ts; focused test/custom_routine_sync_test.dart and backend/tests custom-payload tests. Do not edit backend/strava, sync scheduling, UI, ios, or l10n.

**Contract:** Routine round-trips an optional typed exerciseDefinitions map serialized under exerciseDefinitions. Only referenced custom exercises are included, with stable original IDs and existing Exercise JSON. Reject malformed definitions and built-in ID overrides. Routine/start resolution uses supplied definitions without mutating another account or silently omitting missing movements. Missing unresolved dependencies block starting with an actionable state. Dependency hydration must preserve custom time/cardio/reps-only behavior and deletion semantics; document the final helper signatures in the task report before UI work.

- [ ] Write failing regression using the production StoreSyncRepository: create built-in + custom routine as guest, adopt account, assert two resolved movements and the same custom mode; deliver its routine payload to a fresh repository and assert the same.
- [ ] Prove old routines/backups without definitions still load; repeat adoption/pull is idempotent; malformed or conflicting dependency definitions leave original data intact and account A cannot alter account B.
- [ ] Implement the contract in the canonical routine serialization/resolution path. Avoid global catalog mutation and new envelope entity types.
- [ ] Run flutter test --no-pub test/custom_routine_sync_test.dart test/sync test/sync_repository_test.dart test/safe_restore_test.dart test/training_programs_test.dart; run affected backend tests/check. Report actual totals.
- [ ] Commit only owned files with fix: preserve custom exercises in synced routines.

Representative acceptance assertion:
```dart
expect(fit.routineExercises(adopted).map((e) => e.id), [builtinId, customId]);
fit.startRoutine(adopted);
expect(fit.session!.exercises.map((e) => e.id), [builtinId, customId]);
```

### Task S: safe Strava retry and useful delivery metadata

**Ownership:** backend/strava/**, new backend/migrations/003_strava_retry.sql only if genuinely necessary; backend/strava/README.md. Do not edit backend/src/protocol.ts, Flutter, shared migrations or deployment configuration.

**Contract:** POST /v1/strava/retry body {workoutId, revision}; job projection adds canRetry boolean and name string. canRetry is true only for a proven pre-submission failure/no POST intent, no uploadId/activityId, same athlete ownership, and latest nondeleted source revision. A valid retry is durable, idempotent and returns the queued/current job. Unknown/sending/processing/confirmed or ambiguous prior submission cannot retry. Reconnect to the same athlete may allow a previously unsent job after explicit action; reconnect to another athlete cannot silently send it. Server enforces eligibility independently of UI flags. Retain existing unsupported/edit/delete safeguards.

- [ ] Write failing PostgreSQL/provider tests: known never-sent auth failure -> reconnect same athlete -> explicit retry -> exactly one create; ambiguous POST -> retry rejected and zero second creates; retry replay idempotent; another account/athlete or deleted/edited source rejected.
- [ ] Implement minimal durable submission evidence and retry route; use existing transactions/account locks/generation fence. Do not infer safe retry merely from a status string.
- [ ] Return canRetry and human-readable workout name in status jobs, preserving old fields.
- [ ] Run npm run check, npm run format:check, and isolated PostgreSQL Strava suite. Report tests and API fields.
- [ ] Commit owned files with fix: recover safely from unsent Strava exports.

### Task C: acknowledged-save and foreground sync scheduling

**Ownership:** lib/services/sync/sync_controller.dart, sync_runtime.dart, store_sync_repository.dart, sync_repository_port.dart if needed; lib/services/local_store.dart; lib/app/app_shell.dart; focused test/sync scheduling tests. Do not edit custom dependency storage internals or provider/UI files.

**Contract:** SyncController.requestSync() is a void, coalesced trigger; controller exposes truthful pending/conflict/last-completed state. Trigger only after acknowledged domain saves with pending work, on app resume and after auth recovery. Keep a bounded periodic fallback for reconnect detection, avoid echo loops from pull/persistence notifications, serialize network cycles, preserve account/generation fences, and drain bounded pending batches promptly rather than waiting one minute per edit. Retain guest/no-config zero-network behavior.

- [ ] Write failing fake-time tests that local durable change starts a push promptly, multiple changes coalesce, resume triggers pull, no-network/guest stay safe, a save during sync causes one follow-up, server pulls do not trigger an endless cycle, and signout cancels scheduled account work.
- [ ] Add acknowledged-save observation in Store and a single scheduling owner in runtime/controller; update AppShell resume through requestSync without coupling domain state to HTTP.
- [ ] Run flutter test --no-pub test/sync test/safe_restore_test.dart test/persistence_test.dart and analyzer for changed code.
- [ ] Commit owned files with fix: synchronize durable iPhone changes promptly.

### Task N: native capability cleanup and delivery scaffold

**Ownership:** ios/** preserving existing signing edits; lib/screens/sync/completed_workout_delivery.dart (scaffold only); focused test/apple native capability checks. Do not edit other Dart/UI/state files.

**Contract:** Keep com.apple.developer.healthkit and existing keychain signing identity. Remove health-records and background-delivery unused entitlements. Preserve com.nickcoleman.gymmane, Nick Coleman's team and intentional Xcode project edits. Add a compile-safe placeholder CompletedWorkoutDelivery({super.key, required String workoutId}) widget in lib/screens/sync/completed_workout_delivery.dart for the next wave to implement.

- [ ] Inspect diff and entitlements; validate plist syntax and no unused clinical/background entitlement remains.
- [ ] Add scaffold class with the exact constructor, returning SizedBox.shrink until Task E replaces it.
- [ ] Build iOS simulator without signing when feasible; report signing/entitlement evidence. No app installation or external Apple publishing from worker.
- [ ] Commit only owned files with fix: align iPhone capabilities with workout export.

## Wave 1: integrate reviewed engine/scaffold contracts

Coordinator reviews task compliance and quality separately for D/S/C/N; creates per-task diff packages and routes important findings back to the owner. Integrate in order N, C, S, D (largest dependency diff last) with explicit merge commits. Later UI tasks start only from this integrated base. Existing API routes and payloads must remain backwards compatible.

## Wave 2: parallel iPhone UI work

### Task U: accessible logging, short setup and honest capabilities

**Ownership:** lib/app/gymmane_app.dart; lib/screens/session_screen.dart (extract focused logging subcomponents if necessary); lib/screens/onboarding_screen.dart; lib/screens/settings_screen.dart; lib/widgets/timer_panel.dart and focused input widgets; test/iphone_accessibility_test.dart and test/iphone_onboarding_test.dart. Do not edit lib/screens/sync/**, engines, ios or generated l10n. Reuse existing localized strings; request any necessary shared string additions from coordinator.

**Contract:** Remove the global 1.15 text cap. Primary workout controls offer >=44x44 logical-point touch regions, never shrink hit targets with FittedBox; support 200% text and wrapping. Keep current set, previous performance and rest feedback convenient on iPhone without introducing a tablet redesign. Add CompletedWorkoutDelivery(workoutId: fit.session!.workoutId!) to completed-session content for the actual selected ID when nonnull, not sessions.last. Make first-page Start training prominent using existing localized start label; keep optional setup accessible. Render no iOS widget actions when AppleCapabilities.current.homeWidgets is false.

- [ ] Write widget tests at 390x844 and 320x568 with 1x/2x text: start/complete workout, effort columns, rest controls and keyboard show no overflow and primary hit regions meet the target. Do not suppress Flutter overflow errors.
- [ ] Test a new user can start offline immediately, optional setup persists, and capability-false iOS hides widget actions while Android remains supported.
- [ ] Integrate Task E's exact scaffold constructor and preserve paused/rest state, swipe/delete safety and existing theme.
- [ ] Run focused new tests plus session, continue_session, session_lock, routine_session_edit, existing onboarding/layout tests and analyzer.
- [ ] Commit owned files with fix: improve accessible iPhone workout logging.

### Task E: completed-workout exports and understandable recovery

**Ownership:** lib/screens/sync/** including replace completed_workout_delivery.dart scaffold; lib/services/sync/healthkit_delivery.dart and store_health_delivery.dart only for delivery refresh/selection; focused test/sync UI/export tests. Do not edit session/settings/onboarding, shared engines, ios, backend or generated l10n. Reuse existing strings; send coordinator a concise list for new localization if required.

**Contract:** CompletedWorkoutDelivery({super.key, required String workoutId}) resolves exactly that durable workout and uses SyncRuntime when available, safely hiding unsupported actions in previews. Separate local save/cloud/Health/Strava states; show name and formatted local date, not UUID in user-facing delivery lists. Keep explicit per-workout confirmation and account fences. No history bulk opt-in. Use server canRetry + POST /v1/strava/retry for safe retry; unknown outcomes show manual-check instructions and no create retry. Refresh delivery candidates after sync/local data change and permission status on resume. Conflict review compares exercises, set counts/reps/weights and deletions before choosing, with existing confirmation safeguards.

- [ ] Write widget tests: completed selected ID is used even when another newer workout exists; guest Health export works without cloud; Strava waits until source synced; known-safe retry enabled, unknown retry absent; account change suppresses stale result; local dates/name visible; sync refreshes candidates; conflicts show the differing sets.
- [ ] Implement focused reusable provider controls instead of duplicating delivery rules in the 2996-line session screen.
- [ ] Run flutter test --no-pub test/sync test/apple/healthkit_adapter_test.dart; report counts and screenshots/capture evidence for iPhone layout if available.
- [ ] Commit owned files with feat: surface workout exports and actionable delivery status.

## Wave 3: independent adversarial integration and release

- [ ] Coordinator applies any requested localization changes in one place and generates translations using existing conventions; no parallel writes to l10n.
- [ ] Fresh reviewers receive diff package + task report and explicitly return spec compliance and quality verdicts. Route important findings back to implementer before release.
- [ ] Run full Flutter tests, analyzer, formatting/diff checks, backend check/build/format/tests with disposable PostgreSQL, real HTTP two-client harness, iPhone simulator build and signed release archive.
- [ ] Physically validate iPhone launch, onboarding, one workout, app interruption/relaunch, rest notification permission, Health permission/save/revision/delete when user interaction is available. Real provider smoke tests require configured accounts; never substitute mock success.
- [ ] Inspect actual NAS/runtime hosting and credentials read-only; choose established production target if present. Never replace openGym or another application's containers/data.
- [ ] Deploy backend only with real HTTPS/auth/secret configuration and verified migrations, backups and health/release identity. Verify public callback and real Strava authorization/upload before enabling its production UI.
- [ ] Publish reviewed commits to the personal fork; upload signed build to existing App Store Connect app/TestFlight if access is available. Git push alone is not mobile deployment. Do not invent a download link or silently submit a public App Store release.
- [ ] Record exact published SHA, server release, build/version, test evidence, and any external prerequisite that prevents deployment. Continue all independent work if one live prerequisite is missing.

## Execution ledger

Plan created before edits. Implementation tasks and Orca Run IDs will be recorded here by the coordinator. No live provider/server status is assumed from old handoffs.
