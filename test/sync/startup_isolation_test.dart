import 'dart:async';
import 'package:gymmane/services/sync/sync_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/sync/store_sync_repository.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'package:gymmane/state/fit_state.dart';
import 'sync_controller_test.dart' show TestAuth, TestRepository, configuration, accountId;

class BrokenRestore extends TestAuth {
  BrokenRestore() {
    session = null;
  }
  @override
  Future<void> restore() async => throw const FormatException('Corrupt saved session');
  @override
  Future<void> signIn(String email, String password) async {
    session = AuthSession(accountId, 'token', 'refresh', DateTime(2100));
  }
}

class BrokenSwitch extends TestRepository {
  @override
  Future<void> selectNamespace(String namespace) async => throw StateError('disk unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sign-in after restore failure resumes exactly one periodic sync timer', () async {
    final timers = <ManualPeriodicTimer>[];
    await runZoned(
      () async {
        final repository = TestRepository();
        final sync = SyncController(
          config: configuration,
          auth: BrokenRestore(),
          repository: repository,
          transport: SyncTransport(
            Uri.parse(configuration.serverUrl),
            MockClient((_) async => http.Response('{"entities":[],"nextCursor":"0","hasMore":false}', 200)),
          ),
        );
        addTearDown(sync.dispose);
        await sync.initialize();
        expect(sync.phase, SyncPhase.needsAuthorization);
        await sync.signIn('person@example.com', 'password');
        expect(repository.applications, 1);
        expect(timers, hasLength(1));
        Future<void> tick() async {
          final finished = Completer<void>();
          void listener() {
            if (!sync.busy && !finished.isCompleted) finished.complete();
          }

          sync.addListener(listener);
          timers.single.fire();
          await finished.future;
          sync.removeListener(listener);
        }

        await tick();
        expect(repository.applications, 2);
        await sync.signOut();
        await sync.signIn('person@example.com', 'password');
        expect(timers, hasLength(1));
        expect(repository.applications, 3);
        await tick();
        expect(repository.applications, 4);
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          expect(duration, const Duration(minutes: 1));
          final timer = ManualPeriodicTimer(callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  });
  test('bad saved auth opens guest without copying private account data into guest', () async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    await fit.persistNow(rethrowErrors: true);
    final repository = StoreSyncRepository(Store.instance);
    await repository.selectNamespace('private-account');
    final private = LoggedSession(DateTime.utc(2026), 60, [], name: 'Private');
    fit.sessions.add(private);
    await fit.persistNow(rethrowErrors: true);
    final sync = SyncController(
      config: configuration,
      auth: BrokenRestore(),
      repository: repository,
      transport: SyncTransport(
        Uri.parse(configuration.serverUrl),
        MockClient((_) async => http.Response('{}', 500)),
      ),
    );
    await sync.initialize();
    expect(Store.instance.repository.namespace, 'guest');
    expect(fit.sessions, isEmpty);
    expect(sync.account, isNull);
    await repository.selectNamespace('private-account');
    expect(fit.sessions.single.id, private.id);
    fit.saveAndExit();
    await fit.persistNow();
    sync.dispose();
  });
  test('failed guest isolation propagates to startup recovery instead of opening normal app', () async {
    final sync = SyncController(
      config: configuration,
      auth: BrokenRestore(),
      repository: BrokenSwitch(),
      transport: SyncTransport(
        Uri.parse(configuration.serverUrl),
        MockClient((_) async => http.Response('{}', 500)),
      ),
    );
    await expectLater(sync.initialize(), throwsStateError);
    sync.dispose();
  });
}

class ManualPeriodicTimer implements Timer {
  ManualPeriodicTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (!isActive) return;
    tick++;
    callback(this);
  }

  @override
  void cancel() => isActive = false;
}
