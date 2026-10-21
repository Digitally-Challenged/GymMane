import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gymmane/models/identity.dart';
import 'package:gymmane/services/persistence/backend_native.dart';
import 'package:gymmane/services/persistence/sync_repository.dart';
import 'package:gymmane/services/sync/sync_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opt in through backend/tests/flutter_sync_harness.ts, never a deployed server.
void main() {
  final environment = Platform.environment;
  final base = environment['GYMMANE_TEST_URL'];
  final account = environment['GYMMANE_TEST_ACCOUNT'] ?? '';
  final token = environment['GYMMANE_TEST_TOKEN'] ?? '';
  final otherAccount = environment['GYMMANE_TEST_OTHER_ACCOUNT'] ?? '';
  final otherToken = environment['GYMMANE_TEST_OTHER_TOKEN'] ?? '';
  sqfliteFfiInit();

  for (final reverse in [false, true]) {
    test(
      'real HTTP/SQL: offline convergence ${reverse ? 'B then A' : 'A then B'}',
      () async {
        final uri = Uri.parse(base!);
        expect(uri.host, '127.0.0.1');
        expect([account, token, otherAccount, otherToken].every((value) => value.isNotEmpty), isTrue);
        final directory = await Directory.systemTemp.createTemp('gymmane_live_sync_');
        final databases = <SqliteBackend>[];
        final client = http.Client();
        final transport = SyncTransport(uri, client);
        addTearDown(() async {
          client.close();
          for (final database in databases) {
            await database.database.close();
          }
          await directory.delete(recursive: true);
        });
        Future<SyncRepository> device(String name) async {
          final database = await SqliteBackend.open(
            '${directory.path}/$name.db',
            factory: databaseFactoryFfi,
          );
          databases.add(database);
          final repository = SyncRepository(database);
          await repository.initialize({});
          await repository.selectNamespace(account);
          return repository;
        }

        final a = await device('a');
        final b = await device('b');
        Future<void> pull(SyncRepository repository, {String? owner, String? jwt}) async {
          final namespace = owner ?? account;
          for (;;) {
            final page = await transport.pull(jwt ?? token, repository.cursor(namespace));
            await repository.applyPullPage(
              namespace,
              jsonList(page['entities']),
              page['nextCursor'] as String,
            );
            if (page['hasMore'] == false) break;
          }
        }

        Future<List<SyncJson>> push(SyncRepository repository) async {
          final pending = await repository.pendingOperations(account);
          if (pending.isEmpty) return [];
          final receipts = await transport.push(token, pending);
          await repository.applyPushResults(account, receipts);
          return receipts;
        }

        Future<void> sync(SyncRepository repository) async {
          await push(repository);
          await pull(repository);
        }

        final routineId = newEntityId();
        final workoutId = newEntityId();
        SyncJson document(String label) => {
          'routines': [
            {'id': routineId, 'n': '$label routine', 'ex': <String>[]},
          ],
          'sessions': [
            {
              'id': workoutId,
              'n': '$label workout',
              'd': '2026-10-20T12:00:00.000Z',
              'dur': 60,
              'ex': <dynamic>[],
              'r': routineId,
            },
          ],
        };
        await a.save(document('seed'));
        await sync(a);
        await pull(b);
        expect(b.load(), a.load());
        expect(await b.pendingOperations(account), isEmpty, reason: 'Remote records must not echo');

        // No network calls between these saves: both devices edit the same base.
        await a.save(document('A offline'));
        await b.save(document('B offline'));
        expect(a.pendingCount(account), 2);
        expect(b.pendingCount(account), 2);
        final first = reverse ? b : a;
        final second = reverse ? a : b;
        final firstLabel = reverse ? 'B offline' : 'A offline';
        final secondLabel = reverse ? 'A offline' : 'B offline';

        // Server commits, but the client does not apply the receipt (lost response).
        final pending = await first.pendingOperations(account);
        final committed = await transport.push(token, pending);
        expect(committed.map((r) => r['status']), everyElement('accepted'));
        final beforeRetry = await transport.pull(token, '0');
        final replay = await transport.push(token, await first.pendingOperations(account));
        expect(replay, committed, reason: 'Retry must return original receipts');
        expect(await transport.pull(token, '0'), beforeRetry, reason: 'Retry must not append changes');
        await first.applyPushResults(account, replay);
        await pull(first);

        final conflictingOps = await second.pendingOperations(account);
        final conflicts = await push(second);
        expect(conflicts.map((r) => r['status']), everyElement('conflict'));
        expect(conflicts, hasLength(2));
        // Conflicting receipts also remain replayable without mutating the server.
        expect(await transport.push(token, conflictingOps), conflicts);
        expect(await transport.pull(token, '0'), beforeRetry);
        await pull(second);
        expect(second.load(), document(secondLabel), reason: 'Local edits must survive conflict');
        final preserved = second.conflicts(account);
        expect(preserved.keys.toSet(), {'routine:$routineId', 'workout:$workoutId'});
        expect(preserved['routine:$routineId']['payload']['n'], '$firstLabel routine');
        expect(preserved['workout:$workoutId']['payload']['n'], '$firstLabel workout');
        expect(second.pendingCount(account), 2);
        expect(await second.pendingOperations(account), isEmpty);

        // Keep local routine, accept remote workout: both resolution paths converge.
        await second.resolveConflict(account, 'routine', routineId, keepLocal: true);
        await second.resolveConflict(account, 'workout', workoutId, keepLocal: false);
        await sync(second);
        await pull(first);
        expect(first.load(), second.load());
        expect(first.load()['routines'][0]['n'], '$secondLabel routine');
        expect(first.load()['sessions'][0]['n'], '$firstLabel workout');
        expect(second.conflicts(account), isEmpty);
        expect(first.pendingCount(account), 0);
        expect(second.pendingCount(account), 0);

        // Even after resolution advances the remote revision, the original receipt is stable.
        expect(await transport.push(token, conflictingOps), conflicts);

        // Switch one real repository to another signed account, reusing entity IDs.
        final primaryDocument = second.load();
        await second.selectNamespace(otherAccount);
        await pull(second, owner: otherAccount, jwt: otherToken);
        final otherBefore = second.load();
        expect((otherBefore['sessions'] as List? ?? []).any((row) => row['id'] == workoutId), isFalse);
        await second.save(document('other account'));
        final otherOps = await second.pendingOperations(otherAccount);
        await second.applyPushResults(otherAccount, await transport.push(otherToken, otherOps));
        await pull(second, owner: otherAccount, jwt: otherToken);
        await pull(first);
        expect(first.load(), primaryDocument, reason: 'Other account cannot overwrite identical entity IDs');
        await second.selectNamespace(account);
        expect(second.load(), primaryDocument);

        // Delete both types on one device and persist the remote tombstones on the other.
        await first.save({'routines': <dynamic>[], 'sessions': <dynamic>[]});
        await sync(first);
        await pull(second);
        expect(second.load()['sessions'], isEmpty);
        expect(second.load()['routines'], isEmpty);
        for (final pair in [('routine', routineId), ('workout', workoutId)]) {
          expect(second.entityMetadata(account, pair.$1, pair.$2)!['deleted'], isTrue);
        }
        final restarted = SyncRepository(second.backend);
        await restarted.initialize({});
        expect(restarted.load(), second.load());
        expect(restarted.cursor(account), second.cursor(account));
        await pull(restarted);
        expect(restarted.pendingCount(account), 0);
        await restarted.selectNamespace(otherAccount);
        expect(
          restarted.load()['sessions'][0]['n'],
          'other account workout',
          reason: 'Tombstones are account scoped',
        );
      },
      skip: base == null
          ? 'Run backend/scripts/test-postgres.sh node --import tsx tests/flutter_sync_harness.ts'
          : false,
    );
  }
}
