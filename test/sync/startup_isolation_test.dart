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
import 'sync_controller_test.dart' show TestAuth, TestRepository, configuration;

class BrokenRestore extends TestAuth {
  BrokenRestore() {
    session = null;
  }
  @override
  Future<void> restore() async => throw const FormatException('Corrupt saved session');
}

class BrokenSwitch extends TestRepository {
  @override
  Future<void> selectNamespace(String namespace) async => throw StateError('disk unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
