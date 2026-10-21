import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/sync/store_sync_repository.dart';
import 'package:gymmane/services/sync/store_health_delivery.dart';
import 'package:gymmane/services/sync/sync_controller.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'package:gymmane/state/fit_state.dart';
import 'sync_controller_test.dart' show TestAuth, accountId, configuration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    await fit.persistNow(rethrowErrors: true);
  });
  tearDown(() async {
    fit.saveAndExit();
    await fit.persistNow();
  });
  test(
    'production adapter isolates accounts, adopts explicitly, commits HTTP receipts and pull without echo',
    () async {
      final guest = LoggedSession(DateTime.utc(2026, 10, 20), 60, [], name: 'Guest workout');
      fit.sessions.add(guest);
      await fit.persistNow(rethrowErrors: true);
      final adapter = StoreSyncRepository(Store.instance);
      await adapter.selectNamespace(accountId);
      expect(fit.sessions, isEmpty);
      expect(await adapter.pendingOperations(accountId), isEmpty);
      await adapter.adoptGuest(accountId);
      expect(fit.sessions.single.id, guest.id);
      final remote = LoggedSession(DateTime.utc(2026, 10, 21), 120, [], name: 'Other device');
      final changes = <SyncJson>[];
      final sync = SyncController(
        config: configuration,
        auth: TestAuth(),
        repository: adapter,
        transport: SyncTransport(
          Uri.parse(configuration.serverUrl),
          MockClient((request) async {
            if (request.method == 'POST') {
              final operations = jsonList(jsonObject(jsonDecode(request.body))['operations']);
              final results = <SyncJson>[];
              for (final operation in operations) {
                final entity = <String, dynamic>{
                  'entityType': operation['entityType'],
                  'entityId': operation['entityId'],
                  'revision': 1,
                  'deleted': operation['deleted'],
                  'payload': operation['payload'],
                  'cursor': '${changes.length + 1}',
                };
                changes.add(entity);
                results.add({
                  'operationId': operation['operationId'],
                  'status': 'accepted',
                  'entity': entity,
                });
              }
              return http.Response(jsonEncode({'results': results}), 200);
            }
            final rows = [
              ...changes,
              {
                'entityType': 'workout',
                'entityId': remote.id,
                'revision': 1,
                'deleted': false,
                'payload': remote.toJson(),
                'cursor': '${changes.length + 1}',
              },
            ];
            return http.Response(
              jsonEncode({'entities': rows, 'nextCursor': '${changes.length + 1}', 'hasMore': false}),
              200,
            );
          }),
        ),
      );
      addTearDown(sync.dispose);
      await sync.sync();
      expect(sync.message, isNull);
      expect(sync.phase, SyncPhase.ready);
      expect(fit.sessions.map((s) => s.id).toSet(), {guest.id, remote.id});
      expect(await adapter.pendingCount(accountId), 0);
      final exports = await exportableWorkouts(Store.instance, syncedOnly: true);
      expect(exports.map((e) => e['entityId']), [guest.id]);
      await adapter.selectNamespace('guest');
      expect(fit.sessions.map((s) => s.id), [guest.id]);
      await adapter.selectNamespace(accountId);
      expect(fit.sessions.map((s) => s.id).toSet(), {guest.id, remote.id});
    },
  );
}
