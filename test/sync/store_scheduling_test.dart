import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:gymmane/services/sync/store_sync_repository.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/state/fit_state.dart';

import 'sync_controller_test.dart' show TestAuth, accountId, configuration;
import 'sync_scheduling_test.dart' show SchedulingTransport;

class ControlledBackend implements StorageBackend {
  Map<String, dynamic>? snapshot;
  Completer<void>? gate;
  bool reject = false;
  @override
  Future<Map<String, dynamic>?> read() async => snapshot;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    await gate?.future;
    if (reject) throw StateError('disk full');
    snapshot = (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = Store.instance;
  late ControlledBackend backend;
  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    backend = ControlledBackend();
    Store.backendFactory = (_) async => backend;
    await store.init();
    await store.repository.selectNamespace(accountId);
  }

  tearDown(() {
    Store.backendFactory = (preferences) async => PreferencesBackend(preferences);
  });

  test('Store signals pending domain saves only after their durable commit', () async {
    await initialize();
    final events = <String>[];
    final subscription = store.acknowledgedSaves.listen(events.add);
    addTearDown(subscription.cancel);
    final workout = LoggedSession(DateTime.utc(2026, 10, 21), 60, [], name: 'Durable');
    backend.gate = Completer<void>();
    final saved = store.save({
      'sessions': [workout.toJson()],
    });
    await pumpEventQueue();
    expect(events, isEmpty);
    backend.gate!.complete();
    await saved;
    await pumpEventQueue();
    expect(events, [accountId]);

    backend.reject = true;
    final rejected = expectLater(store.save({'sessions': []}), throwsStateError);
    await rejected;
    await pumpEventQueue();
    expect(events, [accountId]);
    expect(store.saveFailed.value, isTrue);
  });

  test('guest and device-only saves produce no pending-work signal', () async {
    await initialize();
    final events = <String>[];
    final subscription = store.acknowledgedSaves.listen(events.add);
    addTearDown(subscription.cancel);
    await store.save({'units': 'lb'});
    await store.repository.selectNamespace('guest');
    await store.save({
      'sessions': [LoggedSession(DateTime.utc(2026), 60, []).toJson()],
    });
    await pumpEventQueue();
    expect(events, isEmpty);
  });

  test('durable workout syncs without UI notification and remote persistence produces no outbox', () async {
    await initialize();
    fit.loadFromStore();
    final transport = SchedulingTransport();
    final sync = SyncController(
      config: configuration,
      auth: TestAuth(),
      repository: StoreSyncRepository(store),
      transport: transport,
      acknowledgedSaves: store.acknowledgedSaves,
    );
    addTearDown(sync.dispose);
    final synchronized = Completer<void>();
    sync.addListener(() {
      if (!sync.busy &&
          sync.phase == SyncPhase.ready &&
          sync.pendingCount == 0 &&
          !synchronized.isCompleted) {
        synchronized.complete();
      }
    });
    final workout = LoggedSession(DateTime.utc(2026, 10, 21), 60, [], name: 'Persist and close');
    fit.sessions.add(workout);
    backend.gate = Completer<void>();
    final saved = fit.persistNow(rethrowErrors: true);
    await pumpEventQueue();
    expect(transport.pushes, 0);
    backend.gate!.complete();
    await saved;
    await synchronized.future.timeout(const Duration(seconds: 5));
    expect(sync.message, isNull);
    expect(transport.pushes, 1);
    expect(sync.pendingCount, 0);
    expect(transport.pulls, 1);
    expect(fit.sessions.single.id, workout.id);
    await fit.persistNow(rethrowErrors: true);
    expect(await store.repository.pendingOperations(accountId), isEmpty);
  });
}
