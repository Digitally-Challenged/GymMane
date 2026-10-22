# GymMane Apple Watch Companion Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for the task and review loop when implementation is authorized. Track the steps below with checkboxes. This document authorizes no implementation, deployment, or account changes by itself.

**Goal:** Add a reliable Apple Watch companion for strength training, starting with wrist set logging and rest timers, then optional live workout recording and imports from Apple Health.

**Architecture:** Keep the Flutter iPhone application and its transactional local repository as the workout authority. Adapt selected native SwiftUI Watch code behind a small, durable WatchConnectivity bridge. Give every command an identity, persist its outcome with the workout change, and reconcile Health recording through one writer per workout.

**Tech stack:** Existing Flutter 3.41.9 / Dart 3.11.5; native SwiftUI, WatchConnectivity and HealthKit; existing iPhone persistence and provider delivery modules. Provisional watchOS minimum: 10, subject to the compatibility gate below.

**Spec:** The behavior inventory and contracts in this document implement Nick's OSS-first request. Supporting source inspection: [private research](../../../doc-personal/research/2026-10-21-apple-watch-open-source.md). Baseline inspected: `aef684e7d3ca4f105e8207c57a15430ce395dd8f`. Private research is local only; public source links below make the implementation choices independently reviewable.

## Delivery and scope

| Milestone | User-visible result | Release condition |
|---|---|---|
| A: Companion | Start on iPhone; see the current exercise on Watch; edit weight/reps, complete sets, see rest countdown and request pause/resume/finish | Stable identities, durable command handling, paired-device tests |
| B: Live recording | Explicitly choose Watch recording; see live heart rate and active energy; save the selected recording to Health | A passes; single-writer recovery and real sensors verified |
| C: Health imports | Preview and selectively import workouts already recorded by Apple Watch or other Health sources | Independent read consent, provenance and deduplication verified |

Each milestone is independently releasable. Milestone A is the first production candidate. B and C must not delay A, and remain disabled until their own gates pass. A complete standalone Watch routine library, Watch-side routine editing, complications, coaching algorithms and cloud accounts on Watch are outside this plan.

## Global constraints

- iPhone remains primary; preserve guest/offline use, account isolation, existing routines/programs, exercise library, images and theme.
- Watch ↔ iPhone uses paired-device transport. It requires no new Synology service, Supabase feature, Strava API, or Watch login. Existing cloud sync remains separate.
- Preserve iPhone bundle `com.nickcoleman.gymmane`, signing team and existing Health sync namespace `com.gymmane.app.workout.`. A Watch bundle must be a valid child of the phone bundle and verified through signing.
- Keep current Flutter versions for the initial implementation. Do not add React Native/Expo or a custom Flutter Watch engine.
- No clinical Health access. Live metrics and historical reads each get an explicit explanation and only the necessary permissions.
- Health/Strava exports remain explicit. Enabling the companion never bulk-exports existing history or silently starts Health recording.
- Heart rate and energy must come from available sensor data; show unavailable data clearly. Keep raw health data local by default; extending server/Strava payloads is separate work.
- The phone remains usable when Watch is absent, incompatible, unpaired, disconnected or denied Health access.
- No implementation workers deploy. Publish only to the personal fork and the authorized release destination; never upstream. Public App Store submission requires its own instruction.

## Open-source reuse decisions

| Source, pinned revision | Reuse | Required adaptation |
|---|---|---|
| [Ischys, MIT](https://github.com/ischys-app/Ischys/tree/c3dbd8e0979ffb876a8dc10b3d2d9ab3230334d0/frontend/targets/ischys-watch) | Selected SwiftUI set editor, rest alarm, finish/pause state machines | Replace phone transport, add workout/set identities, replace time-based Health fallback; keep GymMane artwork/fonts |
| [strength_tracker, MIT](https://github.com/GunnarStrandbergAB/strength_tracker/tree/fdc50652192f5ddcd95351ba7f8033a5b6c99db9/StrengthTracker) | Health session/builder and recovery patterns | Map to GymMane identity/persistence; scope every terminal event to its workout |
| [Skulpt, GPLv3](https://github.com/skulptapp/skulpt/tree/538363e70d8cf5a9832eddf4e9d06a6e931446cb) | Reference for native durable inbox and expected-state commands | Replace Expo bindings; atomically commit receipts with domain changes; no bounded-only dedup window |
| [Iron, GPLv3](https://github.com/karimknaebel/Iron/tree/de02504fca4b0721b26e315f3755fc4878d397ae) | Secondary reference for session-scoped events | Older implementation; do not import wholesale |

Record exact donor files/revisions and retain notices for copied code in `CREDITS.md` and `ios/WatchApp/ThirdPartyNotices.txt`. The researched MIT code does not license the donor's separate artwork/fonts. Source inspection has not proved any donor reliable on our devices.

Prefer extending our native bridge. The inspected `watch_connectivity` 0.2.9–0.2.11 require a newer SDK; the compatible 0.2.8 wrapper does not supply our complete durable transport contract. `health` 13.3.2 is an optional import adapter only if a spike proves it smaller and compatible; it must not introduce a second Health export implementation.

## Review focus

1. Delayed or repeated commands must never change a different workout, exercise occurrence, set or account. Tasks 1–3 own these tests.
2. A process crash between receipt, local commit and acknowledgement must produce one domain effect and a recoverable outcome. Tasks 2–3 own these tests.
3. Units, edited/reordered sets, pause and final-set completion must behave consistently on both devices. Tasks 1, 3 and 4 own these tests.
4. Watch and iPhone must never independently save two Health workouts after an uncertain result. Task 5 owns these tests.
5. Importing Health history must preserve provenance, avoid export loops and handle unavailable/revoked reads without claiming there is no history. Task 6 owns these tests.

## Behavior and interface contracts

### Workout identity and command processing

Current `SessionSet` has no stable ID; `SessionExercise.id` is the catalogue ID, not an occurrence ID. Current `toggleSetAt` toggles by list index. Those are prerequisites to repair before accepting Watch mutations.

- Add immutable `setId` and `occurrenceId`; preserve catalogue IDs. Generate once, persist, preserve on reorder/edit/restore, and create new IDs when cloning a new workout. Migrate legacy active sessions atomically before publishing a Watch snapshot; deterministic migration uses workout identity and original occurrence/set position, never receipt-time indices.
- Persist `sessionRevision` for every relevant phone or Watch mutation. Persist a per-set `setRevision` for weight/reps/completion edits. Phone and Watch must use one mutation path so phone edits cannot escape revision checks.
- Use an opaque `bindingId` for the current installation/account binding; never send account email or auth tokens. Rotate it on sign-in/out, account switch, backup replacement and re-pair/rebind. Old commands remain rejected even if a workout UUID reappears.
- `completeSet` assigns values and `done=true`; it never toggles. Replaying its `commandId` returns the stored receipt. An explicit later phone undo increments `setRevision` and cannot be undone by replay.
- Snapshot shape: `schemaVersion`, `bindingId`, `workoutId`, `sessionRevision`, phase, current occurrence/set IDs, supported set fields/revisions, unit preference, UTC rest deadline or frozen remaining seconds. Include all remaining supported sets so disconnected logging can advance locally.
- Command shape: `schemaVersion=1`, `commandId` UUID, `bindingId`, `workoutId` UUID, `deviceSequence`, `action`, `expectedSessionRevision`; set edits also carry `occurrenceId`, `setId`, `expectedSetRevision`, `weightKg`, `reps`. Sequence is persisted on Watch and commands are processed serially per binding.
- Set commands use target-set revision plus membership/phase checks; unrelated set edits do not invalidate the entire offline queue. Session actions require the current session revision. A preceding gap waits for replay; no later command silently overtakes it. A rejected command resolves its sequence and refreshes the snapshot.
- Allow `completeSet`, `pause`, `resume`, `skipRest`, `finish`. Initial Watch UI does not offer destructive discard. Validate numeric types, finite/nonnegative weights, integer reps, identity, bounds and supported modes at both native and Dart entry points; use the existing phone limits.
- Result states: `applied`, `rejected`, `retryable`; include `commandId`, reason and resulting revision. Only applied/permanently rejected outcomes are terminal acknowledgements. A duplicate terminal command returns its original receipt, even after newer edits.
- Atomically persist domain document + terminal receipt through `SyncRepository`. Publish UI state/effects only after commit. Native inbox removal follows that receipt; a transport-level acknowledgement only means safely queued. Retain receipts through binding/session closure; compact only after closing that binding so old deliveries cannot reapply.
- Persist effect intents with stable IDs where a crash after commit could lose required finalization. Recover rest from its deadline; reconcile pending finish against current session identity/revision. Set completion and workout finalization are distinct durable outcomes, so the Watch cannot call a workout saved merely because the last set was accepted.
- Existing `Store.acknowledgedSaves` only signals cloud work for signed-in accounts. It is not a suitable Watch update trigger for guest mode. Add a separate committed-session observation at the durable mutation seam.
- Preserve existing rest, linked exercises, effort, auto-advance, finish and routine rotation semantics. Timer/audio effects occur once after commit; final-set completion uses the existing finish policy and its durable-save failure behavior.

### Watch communication and screen behavior

- One native `WCSession` delegate per device. Activate the phone delegate before the Flutter engine is ready and persist incoming commands without needing Dart execution. Drain on engine ready/foreground; do not promise iOS will launch/run Dart for every background message.
- Watch persists commands before sending. Use reachable messages for latency, `transferUserInfo` for eventual queued actions, and `updateApplicationContext` only for replaceable snapshots. Every delivery path deduplicates the same IDs; reachability loss uses the durable queue.
- A shows waiting/current exercise, weight/reps with visible units and Crown focus, complete set, rest, pause and finish confirmation. Preserve GymMane's dark/accent theme with native Watch typography, VoiceOver, Dynamic Type, large targets and text status labels.
- Show `Saved on Watch · waiting for iPhone` for queued edits; only show phone acceptance after durable acknowledgement. Phone unavailable means progress may remain pending until it runs again. Stale/conflicting edits offer clear refresh/review on iPhone, never silent overwrite.
- Use absolute UTC deadlines and frozen pause values. A has no dummy Health session to keep the timer alive: verify notification behavior on hardware and describe delivery limits. Ignore expired/stale alarms; persist alarm identity to prevent repeat haptics after restart. Coordinate phone/Watch alert preference to avoid two intentional alarms for one rest.
- Reps/weight strength sets are writable first. Timed holds, distance modes or unsupported mixed sets show `Continue on iPhone` and retain the correct current position; do not coerce them into strength sets.
- Offline operation uses the last acknowledged workout snapshot plus durable pending commands. Changing to a different workout on the phone rejects old queued edits and leaves a visible recoverable result. Full standalone Watch workout creation is deferred.

### Health recording and imports

- A continues the existing explicit phone summary export. B adds an explicit per-workout `Record on Watch` choice before starting a live Health session; explain that it starts sensors and offer Save to Health/Discard recording at finish. GymMane's set history still saves if Health permission/save fails.
- Persist writer ownership (`phoneSummary` or `watchRecording`) before a writer starts. Selecting Watch reserves ownership on the phone before a start acknowledgement; if the phone is unavailable, A still works and new live recording waits. Never start the phone writer while Watch ownership is pending or uncertain.
- Watch recording uses `HKWorkoutSession`/`HKLiveWorkoutBuilder`, handles pause/resume/interruption/recovery, and sends a durable receipt containing GymMane workout ID, recorded revision, writer device and Health workout UUID. A summary revision is distinct from the active session revision.
- Preserve stable sync metadata, but do not assume identical metadata deduplicates Health saves from different phone/Watch sources. An unknown save result remains pending reconciliation; there is no timed fallback to a second writer. Editing/deleting a Watch-owned export must route to its owner or show an explicit unsupported/pending state.
- Reconcile a recovered Health session to persisted workout identity. Do not discard a valid session solely because the process restarted. Test missing phone, account change and interrupted finish before allowing recovery UI to claim success.
- C is independently opt-in: request workout reads only for basic history; ask separately for HR/energy if offered. Historical imports work on iPhone without a companion. The picker previews source/date/type/duration and requires selected confirmation.
- Import identity is the Health sample UUID plus source provenance; exclude GymMane phone/Watch sources and known own export IDs. Label imported summaries, preserve duration/source, and do not invent exercises or sets. Do not automatically export imported workouts to Health or Strava.
- Persist import selections, source IDs, deletion tombstones and query anchors atomically. First release refreshes while foregrounded; no background-delivery entitlement. A source deletion must be surfaced for review, never erase a locally edited workout silently. Missing data under Health privacy restrictions is not proof of permission denial or an empty history.

## Execution waves and ownership

No workers are launched for plan generation. On execution, use the existing supervised worker workflow, current supported models, and a fresh reviewer for each workstream. Every worker is sharing the codebase: do not revert others or edit outside ownership. Shared-contract changes return to the coordinator.

| Wave | Owner / future branch | Exact responsibility | Dependency |
|---|---|---|---|
| Spike | Native scaffold, `feat-watch-native-bridge` | Task 0; minimal target, packaging and compatibility proof | Existing phone baseline |
| 0 | Core, `feat-watch-session-contract` | Tasks 1–2; shared Dart models, command reducer, persistence, tests | Compatibility spike |
| 1 | Native scaffold, `feat-watch-native-bridge` | Task 3; Xcode/config, phone native transport, bridge registration, empty Watch target | Wave 0 contracts frozen |
| 2A | Watch UI, `feat-watch-workout-ui` | Task 4; `ios/WatchApp/**` except files reserved below; Watch UI tests | Waves 0–1 |
| 2B | Phone UI, `feat-watch-phone-controls` | Task 4; `lib/screens/sync/watch_section.dart`, sync-screen integration, corresponding localization and widget tests | Waves 0–1 |
| 3 | Integration coordinator | Milestone A integration/device/release gate | Merge 2B then 2A |
| 4 | Health recording, `feat-watch-health-recording` | Task 5; reserved `ios/WatchApp/Health/**`, Health delivery/persistence extensions and tests | A accepted |
| 5 | Health imports, `feat-health-workout-import` | Task 6; isolated import modules, picker, Health bridge reads and tests | Recording contract frozen; independent release |

Integrate the accepted spike before Wave 0, then resume the native scaffold work on the integrated core contracts in Wave 1. Waves 0–1 are serial because shared identity, schema and native configuration are coupled. Only 2A/2B run concurrently. The phone UI worker alone owns localization files; Watch text/resources belong to 2A. Transport files and shared protocol types are frozen for UI workers. Wave 4 owns later edits to all Health writer files; Wave 5 begins after that shared-file work is merged. No concurrent worker owns `project.pbxproj`.

Use the primary checkout for planning. At execution, validate descriptive branch/workspace names; reuse a suitable checkout and create additional Orca-managed worktrees only for actual concurrent file isolation. Do not recreate retired worktrees. Record test totals, reviewed SHAs and measured runtime/cost when available; do not invent spend numbers.

## Tasks

For every implementation task: write the named failing tests, verify the expected failure, implement, run the scoped checks, then obtain separate spec-compliance and code-quality verdicts before dependent work starts. Commit only explicit owned paths when execution includes commits. Each branch gets a fresh adversarial review before integration.

### Task 0: Prove native packaging and paired-device compatibility

**Files:** `ios/Runner.xcodeproj/project.pbxproj`, new `ios/WatchApp/GymManeWatchApp.swift`, `ios/WatchApp/Info.plist`, `ios/WatchApp/WatchApp.entitlements`, `ios/WatchAppTests/WatchSmokeTests.swift`. Native scaffold owner retains these files through Task 3.

- [ ] Inventory the installed Xcode SDKs and Nick's Watch model/watchOS; verify paired hardware is available. Keep watchOS 10 as the target floor only if the installed toolchain/dependencies support it. Record any changed minimum before further implementation.
- [ ] Create a minimal native Watch companion, embed it in Runner, and verify signing/archive structure with the existing phone identity. No Health capability is needed for A's smoke screen.
- [ ] Build and launch paired simulators; use `xcodebuild -list` and `-showdestinations` to record actual shared scheme/destination names. Build a signed development archive and install the empty companion on the paired Watch.
- [ ] Exit gate: Watch launches with the existing iPhone app, plugin registration still works, and the generated archive includes the Watch product. If hardware is absent, software work can continue, but A cannot be marked device-validated or released as proven.

### Task 1: Add stable live-session identities and a pure command reducer

**Modify:** `lib/models/live_session.dart`, `lib/services/migration/identity_migration.dart`, `lib/state/workout_state.dart`, `lib/state/fit_state.dart` only at the mutation/persistence seam.
**Create:** `lib/services/watch/watch_protocol.dart`, `lib/services/watch/watch_command_reducer.dart`.
**Tests:** `test/watch/session_identity_test.dart`, `test/watch/watch_command_reducer_test.dart`; extend `test/live_session_test.dart` and `test/safe_restore_test.dart` as needed.

**Produces:** `WatchCommand.fromJson(Map<String, dynamic>)`, `WatchSnapshot.fromJson(Map<String, dynamic>)`; pure `WatchTransition reduceWatchCommand(WatchSessionState state, WatchCommand command)`. Internal `WatchSessionState` contains the full cloned workout, including unsupported sets, pause state, binding and revisions; `setById(String)` addresses its stable IDs. Transition exposes `next`, `receipt`, and deferred `effects`; `StartRestEffect` is a typed effect with a stable ID and deadline. State, command, snapshot and receipt serialize through `toJson()`; receipt exposes `status`, `reason`, `commandId`, `sessionRevision`. The wire snapshot is a projection, never the authority used to decide whether the whole workout is finished.

- [ ] Write migration tests proving IDs survive serialize/restore/reorder; two occurrences of the same exercise have distinct IDs; a newly started/cloned routine has new IDs; repeated legacy migration is byte-equivalent. Reject duplicate supplied IDs without damaging the original document.
- [ ] Write reducer tests for stale target-set revision, a deleted/reordered target, new workout/binding, unsupported schema/mode, invalid numbers, kg/lb conversion, final set, linked sets and pause/rest. Literal assertion shape:

```dart
final next = reduceWatchCommand(snapshot, command);
expect(next.next.setById(command.setId!).done, isTrue);
expect(next.next.setById(otherSetId).done, isFalse);
expect(reduceWatchCommand(changedSetSnapshot, command).receipt.reason,
    'staleSet');
expect(reduceWatchCommand(otherBindingSnapshot, command).receipt.reason,
    'bindingChanged');
```

- [ ] Implement the types and reducer, sharing the relevant phone domain rules rather than introducing a second set of finish/rest rules. Route phone edits through revision updates; expose state changes only after the eventual repository commit.
- [ ] Run `flutter test --no-pub test/watch/session_identity_test.dart test/watch/watch_command_reducer_test.dart test/live_session_test.dart test/session_test.dart test/continue_session_test.dart test/safe_restore_test.dart`; expect all pass. Review before Task 2 consumes the contract.

### Task 2: Commit workout changes and command receipts atomically

**Modify:** `lib/services/persistence/sync_repository.dart`, `lib/services/local_store.dart`, the Task 1 mutation seam.
**Create:** `lib/services/watch/watch_command_processor.dart`.
**Tests:** `test/watch/watch_command_processor_test.dart`, `test/watch/watch_repository_test.dart`.

**Produces:** `Future<WatchReceipt> WatchCommandProcessor.accept(WatchCommand command)`; `Stream<WatchSnapshot> get committedSnapshots`; repository transaction accepts the command against the latest persisted session and stores receipt + document together. Do not load, mutate and save outside that serialized transaction. Expose a focused repository method, keeping reducer logic out of the storage backend.

- [ ] Using an injected storage backend and fake clock, prove duplicate receipt replay, crash/restart after commit before native acknowledgement, crash before pending effects execute, write failure rollback, concurrent phone edit, sign-out during commit, backup replacement and guest mode. Assert replay does not restart rest/finish/rotation effects; recovered finish intent either finalizes once or is superseded by a newer edit.

```dart
final first = await processor.accept(command);
final again = await processor.accept(command);
expect(again.toJson(), first.toJson());
expect(repository.load()['live'], committedLiveDocument);
expect(effects.whereType<StartRestEffect>(), hasLength(1));
// With backend failure injected before commit:
expect(failed.status, WatchReceiptStatus.retryable);
expect(repository.load(), originalDocument);
expect(publishedSnapshots, isEmpty);
```

- [ ] Persist the sequence/receipt ledger outside cloud entity payloads. Ensure existing namespace transactions cannot rebind an in-flight command to another account. A gap requests missing replay and retains later commands; a permanent rejection resolves its sequence.
- [ ] Wire committed snapshots independently of signed-in cloud outbox notifications. Ensure normal phone/guest edits and finish failures produce truthful Watch state.
- [ ] Run `flutter test --no-pub test/watch test/sync_repository_test.dart test/persistence_test.dart test/session_lock_test.dart test/sync/healthkit_ownership_test.dart`; expect all pass, including process-recreation fixtures. Review and freeze shared types before Wave 1.

### Task 3: Durable native transport and Flutter adapter

**Modify:** `ios/Runner/AppDelegate.swift`; Task 0 Xcode/config files; phone lifecycle registration where necessary.
**Create:** `ios/Runner/WatchConnectivityBridge.swift`, `ios/Runner/WatchCommandInbox.swift`, `ios/WatchShared/WatchEnvelope.swift`, `ios/WatchApp/Connectivity/PhoneLink.swift`, `lib/services/watch/watch_adapter.dart`, `lib/services/watch/watch_runtime.dart`.
**Tests:** `ios/RunnerTests/WatchCommandInboxTests.swift`, `ios/WatchAppTests/PhoneLinkTests.swift`, `test/watch/watch_adapter_test.dart`; shared fixtures under `test/fixtures/watch/` included in native tests.

**Produces:** Method channel `gymmane/watch`: `status`, `drainCommands`, `ackCommand`, `publishSnapshot`; event channel `gymmane/watch/events` signals queue/status changes. Native transport is available before Flutter; `WatchRuntime` serially drains through Task 2. `WatchAdapter` exposes typed status, pending commands, terminal acknowledgement and snapshot publication.

- [ ] Write native tests: receive while Flutter absent, persist/restart/drain, lost acknowledgement, duplicate message/user-info delivery, malformed/property-list/oversized input, reachability failure and account rebinding. Write Dart tests that native acknowledgement never precedes durable acceptance and guest snapshots are delivered.

```dart
await runtime.drain(); // Inject a repository write failure.
expect(nativeInbox.terminalAcknowledgements, isEmpty);
expect(nativeInbox.pendingCommandIds, contains(command.commandId));
await runtime.drain(); // Storage recovers; same command is retried.
expect(nativeInbox.terminalAcknowledgements, [command.commandId]);
```

- [ ] Implement durable on-device queues with protected app storage, limits that visibly refuse new actions rather than dropping old ones, and shared JSON fixtures decoded in Swift/Dart. Only terminal receipts remove commands. Native acknowledgement failure is retried safely.
- [ ] Activate exactly one phone WCSession delegate early; register the Flutter adapter with the existing implicit engine pattern. Empty/unsupported platforms return an unavailable status without breaking startup.
- [ ] Run scoped Flutter tests, native tests through the schemes recorded in Task 0, `flutter analyze`, and `flutter build ios --simulator --no-pub`. Expected: all pass; inspect archive embedding again after final project edits. Freeze project/config and adapter signatures before parallel UI work.

### Task 4: Watch workout screens and iPhone connection controls

**2A creates:** `ios/WatchApp/Workout/{WorkoutViewModel,ActiveSetView,RestView,FinishView}.swift`, `ios/WatchApp/Timing/RestAlarm.swift`, Watch localization/resources, `ios/WatchAppTests/{WorkoutViewModelTests,RestAlarmTests}.swift`, `ios/WatchAppUITests/WorkoutFlowTests.swift`. It may modify Task 0's app entry after scaffold handoff. Health files remain reserved for Task 5.
**2B creates:** `lib/screens/sync/watch_section.dart`, `test/watch/watch_section_test.dart`.
**2B modifies:** `lib/screens/sync/sync_screen.dart` and only required existing localization source/generated files under `lib/l10n/`.

**Consumes:** Task 3 typed adapter; Task 1 snapshot/command contract. `WatchSection({super.key})` follows existing provider-section construction. `WorkoutViewModel` renders acknowledged state plus a persisted pending overlay, with connection and acknowledgement status separate.

- [ ] 2A writes tests: 100 kg → lb display → edit → canonical kg round-trip; Crown focus never changes both fields; complete set queues once on double tap; offline progression retains original IDs; stale rejection restores authoritative values; final set awaits phone finish confirmation; timed hold shows `Continue on iPhone`.
- [ ] 2A writes fake-clock rest tests: pause freezes remaining time; resume creates a new deadline; restart does not repeat an alarm; reordered snapshots cannot resurrect an old timer. Snapshot revision 11 followed by 10 keeps 11. Binding change clears displayed prior-account data but retains isolated pending records for reconciliation.
- [ ] 2A adapts selected OSS Swift screens/state machines, preserving notices and GymMane styling. Finish confirmation distinguishes `Waiting for iPhone` from `Workout saved`; losing the phone does not falsely report a completed save.
- [ ] 2B writes widget tests for not paired, not installed, unreachable, pending and connected states; no cloud sign-in required; oversized text; no raw diagnostic/credential copy. Phone controls explain set logging separately from Health recording.

```swift
model.receive(snapshotAtRevision11)
model.receive(snapshotAtRevision10)
XCTAssertEqual(model.sessionRevision, 11)
model.completeCurrentSet()
model.completeCurrentSet()
XCTAssertEqual(outbox.commands.count, 1)
XCTAssertEqual(model.statusText, "Saved on Watch · waiting for iPhone")
```

- [ ] Run `flutter test --no-pub test/watch/watch_section_test.dart` and the native unit/UI targets recorded in Task 0. Review screenshots on small/large Watch sizes and iPhone at 200% text. Then review each workstream independently and integrate 2B before 2A.

### Task 5: Optional live Watch recording with one Health writer

**Create:** `ios/WatchApp/Health/{WatchWorkoutRecorder,RecordingRecovery}.swift`, `lib/services/watch/watch_recording_coordinator.dart`, focused native/Flutter tests in existing Watch and `test/sync/` suites.
**Modify:** `ios/WatchApp/WatchApp.entitlements`, Watch Health usage descriptions; existing `ios/Runner/HealthKitBridge.swift`, `ios/Runner/HealthKitWorkout.swift`, `lib/services/sync/healthkit_delivery.dart`, `lib/services/persistence/health_delivery_registry.dart`, `lib/services/persistence/sync_repository.dart` only for writer policy; Watch finish/settings UI and phone Health delivery details.

**Produces:** `Future<RecordingDecision> WatchRecordingCoordinator.reserve(String workoutId)` and `Future<void> reconcile(WatchRecordingReceipt receipt)`; decisions distinguish ready, pending, denied and unavailable. Receipt contains workout identity, binding, recording revision, writer device, outcome and optional Health UUID. Native recorder owns all HKWorkoutSession/builder callbacks.

- [ ] Write tests: Watch reservation blocks phone summary export; duplicate/late save receipt is idempotent; unknown save outcome never falls back; account switch cannot adopt another workout; failed Health save preserves GymMane history; restart reconciles the same session; phone edit/delete of Watch-owned record routes or blocks truthfully.

```dart
expect(await phoneWriter.canSubmit(watchReservedWorkout), isFalse);
await coordinator.reconcile(unknownSaveReceipt);
expect(await phoneWriter.canSubmit(watchReservedWorkout), isFalse);
await coordinator.reconcile(savedReceipt);
await coordinator.reconcile(savedReceipt);
expect(ledger.healthWorkoutIds(workoutId), [savedReceipt.healthWorkoutId]);
expect(phoneWriter.submissions, isEmpty);
```

- [ ] Adapt native Health recording/recovery patterns, request only actual live metric permissions, and add workout-processing background support only for real recording. Distinguish recording completion from Health save outcome; throttle metric snapshots and avoid persisting HR every screen tick.
- [ ] Implement reserve/start/end/save/discard handshakes and durable receipts. Keep the existing metadata namespace and summary-export behavior for phone-owned workouts. Validate update/delete support across actual phone/Watch Health sources instead of assuming metadata grants ownership.
- [ ] Run recording/writer/ownership tests, native builds and physical Health checks from the gate below before enabling B. Do not claim simulator HR/calorie output verifies sensors.

### Task 6: Optional selective import of Apple Health workouts

**Create:** `lib/services/integrations/healthkit/healthkit_import_adapter.dart`, `lib/services/health_import/{health_import_controller,health_import_repository}.dart`, `lib/screens/sync/health_import_sheet.dart`, `test/apple/healthkit_import_test.dart`, `test/sync/health_import_repository_test.dart`.
**Modify:** existing native HealthKit bridge for reads; focused import seam in `lib/state/fit_state.dart`, `lib/models/workout.dart` only if provenance cannot use existing fields; `lib/screens/history_screen.dart` for source-labelled summaries without set details; connection UI/localization owned serially here.

**Produces:** `HealthImportController.preview()` returns source-labelled candidates; `importSelected(Set<String> sampleIds)` commits selected summaries and provenance atomically. Native read adapter uses anchored workout queries; first page and subsequent anchor/deletion events share the same repository transaction model. No separate Health writer.

- [ ] Write tests: same sample imported twice/restarted once; same-looking workouts from distinct source UUIDs remain distinct; own phone/Watch exports excluded; selected IDs only; no fabricated sets; source deletion/revoked or unavailable reads; edited imported history retained; imported rows ineligible for automatic provider exports; namespace switch fences an in-flight page.

```dart
await controller.importSelected({externalSampleId});
await controller.importSelected({externalSampleId});
expect(repository.importedSampleIds, {externalSampleId});
expect(importedWorkout.origin, 'healthkit');
expect(importedWorkout.exercises, isEmpty);
expect(await healthWriter.canSubmit(importedWorkout), isFalse);
expect(await stravaWriter.canSubmit(importedWorkout), isFalse);
```

- [ ] Implement a foreground preview/confirmation sheet and store source identity, anchors and tombstones with the selected account/guest namespace. Render summary-only imported workouts in history/detail without expecting a first exercise; test that path. Explain that selected summaries follow the existing account cloud-sync setting, while raw sensor series stay local. On source deletion, flag for review; retain locally edited history. Display read limitations without inferring authorization from empty results.
- [ ] Extend the existing native bridge unless an isolated dependency/build comparison demonstrates the optional `health` package reduces code without overlapping exports. Record that choice before adding a package.
- [ ] Run import tests, existing backup/restore and provider eligibility tests, analyzer and native build; verify a real external Watch workout imports once while GymMane exports remain excluded. C can ship independently of whether live GymMane Watch recording is enabled.

## Integration, physical acceptance and release

- [ ] Before A, test two sets at normal speed and while disconnected; reconnect/restart apps; confirm exactly one completion per set, correct rest/auto-advance, original units and no wrong-workout mutations. Repeat as guest and signed in, without NAS connectivity.
- [ ] Test phone locked, phone app terminated/force-quit, Watch app restart, Bluetooth/range loss, reboot, low power, delayed finish after a new workout, account switch and backup restore. Record which states require opening the phone; pending status must match observed platform limits.
- [ ] Test rest alerts while wrist lowered/app backgrounded, permission denied and alert preference changed; measure late/missed alerts and battery use over a representative full workout. These results are release evidence, not assumptions.
- [ ] Before B, exercise grant/deny/revoke, pause/interruption, discard, save failure/unknown result, recovery and selected save. Confirm exactly one workout with correct duration/source in Health/Fitness, actual HR/energy when available, and no second phone summary. Verify revision/delete behavior or its explicit limitation.
- [ ] Before C, import one Apple Watch workout, repeat refresh/relaunch, delete its source, change accounts and revoke access. Confirm provenance, deduplication and no Health/Strava export loop.
- [ ] Run the full native Flutter verification and applicable native tests; inspect `pubspec.yaml` and CI for the pinned formatter/lint commands. For unchanged backend contracts, no backend migration/deployment is needed. Explain every skipped check and do not reuse pre-Watch passing totals as Watch evidence.
- [ ] Fresh-context adversarial review covers the merged diff, native/Dart fixtures, identity migration, command crash windows, account isolation, Health writer ownership and device evidence. High/medium defects block the corresponding milestone.
- [ ] Archive the iPhone with embedded Watch app; verify bundle identities/entitlements and distribution signing. Query the latest App Store Connect build number before incrementing; distribute through the existing internal TestFlight route, then test installing/updating both products from that archive.
- [ ] Keep separate persisted local flags for companion, recording and imports. Disabling a feature stops new actions but retains pending commands/recordings/receipts and exposes recovery. Do not downgrade into an old phone build while a Watch owns an unfinished recording. Rollback must preserve history and complete reconciliation before switching writers.
- [ ] Publish only after that milestone's gates pass and execution/release is authorized. Verify the personal fork ref, uploaded build and actual installation; update the existing local handoff with SHAs, results, remaining hardware limits and OSS notices.

## Inputs and completion evidence

Planning needs no credentials or additional account setup. Before physical acceptance we need a paired Apple Watch, its model/watchOS version, and Nick wearing it for a representative workout. Grant sensor/read permissions only when testing the relevant opt-in feature. Do not ask for Apple passwords or Strava secrets for the local companion.

Milestone A is complete only with durable set/rest behavior and paired-device evidence. B additionally needs actual sensor/Health single-writer evidence; C needs selective-import/provenance evidence. No dates or production-readiness claims follow merely from finding matching open-source code.
