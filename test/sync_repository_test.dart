import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/identity.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/migration/identity_migration.dart';
import 'package:gymmane/services/persistence/backend_native.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:gymmane/services/persistence/sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FailingBackend implements StorageBackend {
  FailingBackend(this.inner);
  final StorageBackend inner;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() => inner.read();
  @override
  Future<void> write(Map<String, dynamic> snapshot) {
    if (fail) throw StateError('Injected disk failure');
    return inner.write(snapshot);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late SqliteBackend sqlite;
  late FailingBackend backend;
  late SyncRepository repository;
  Map<String, dynamic> workout({String? id, String name = 'A'}) => LoggedSession(
    DateTime.utc(2026, 1, 1),
    120,
    [
      LoggedExercise('catalog-id', 'Bench', 'chest', [LoggedSet(8, 60)]),
    ],
    id: id,
    name: name,
  ).toJson();
  Map<String, dynamic> remote(Map<String, dynamic> payload, int revision, {bool deleted = false}) => {
    'entityType': 'workout',
    'entityId': payload['id'],
    'revision': revision,
    'deleted': deleted,
    'payload': deleted ? null : payload,
    'cursor': '$revision',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gymmane_sqlite');
    sqlite = await SqliteBackend.open('${directory.path}/state.db', factory: databaseFactoryFfi);
    backend = FailingBackend(sqlite);
    repository = SyncRepository(backend);
    await repository.initialize({});
  });
  tearDown(() async {
    await repository.flushed;
    await sqlite.database.close();
    await directory.delete(recursive: true);
  });

  test('legacy migration is repeatable and remaps all routine references', () {
    final oldWorkout = workout()..remove('id');
    oldWorkout['r'] = 'r-old';
    final legacy = {
      'routines': [
        {
          'id': 'r-old',
          'n': 'Push',
          'ex': ['catalog-id'],
        },
      ],
      'sessions': [oldWorkout],
      'weeklyPlan': {'1': 'r-old'},
      'planExtras': {
        '1': ['r-old'],
      },
      'planMoves': {
        '2026-01-01': ['r-old'],
      },
      'rotationIds': ['r-old'],
      'rotationNext': 'r-old',
      'live': {'r': 'r-old'},
    };
    final migrated = migrateIdentities(legacy);
    final id = (migrated['routines'] as List).single['id'];
    expect(isEntityId(id), isTrue);
    expect(migrated['weeklyPlan']['1'], id);
    expect(migrated['planExtras']['1'], [id]);
    expect(migrated['planMoves']['2026-01-01'], [id]);
    expect(migrated['rotationIds'], [id]);
    expect(migrated['rotationNext'], id);
    expect(migrated['live']['r'], id);
    expect(migrated['sessions'][0]['r'], id);
    expect(migrated['routines'][0]['ex'], ['catalog-id']);
    expect(migrateIdentities(legacy), migrated);
    expect(migrateIdentities(migrated), migrated);
    expect(legacy['weeklyPlan'], {'1': 'r-old'});
  });

  test('failed local commit leaves both durable state and outbox unchanged', () async {
    await repository.selectNamespace('alice');
    final row = workout();
    backend.fail = true;
    await expectLater(
      repository.save({
        'sessions': [row],
      }),
      throwsStateError,
    );
    expect(repository.load()['sessions'], isNull);
    expect(await repository.pendingOperations('alice'), isEmpty);
    backend.fail = false;
    await repository.save({
      'sessions': [row],
    });
    final restarted = SyncRepository(backend);
    await restarted.initialize({});
    expect(restarted.load()['sessions'], [row]);
    expect(await restarted.pendingOperations('alice'), hasLength(1));
  });

  test('serialized edits retain replay identity and rebase unsent successor after receipt', () async {
    await repository.selectNamespace('alice');
    final row = workout();
    final edit = {...row, 'n': 'Edited'};
    await Future.wait([
      repository.save({
        'sessions': [row],
      }),
      repository.save({
        'sessions': [edit],
      }),
    ]);
    final first = (await repository.pendingOperations('alice')).single;
    expect(first['payload'], row);
    expect((await repository.pendingOperations('alice')).single, first);
    await repository.applyPushResults('alice', [
      {'operationId': first['operationId'], 'status': 'accepted', 'entity': remote(row, 1)},
    ]);
    final second = (await repository.pendingOperations('alice')).single;
    expect(second['payload'], edit);
    expect(second['baseRevision'], 1);
    expect(second['operationId'], isNot(first['operationId']));
    expect(repository.load()['sessions'], [edit]);
  });

  test('pull cursor is atomic, conflicts preserve local edits and explicit resolution rebases', () async {
    await repository.selectNamespace('alice');
    final row = workout();
    await repository.save({
      'sessions': [row],
    });
    final theirs = {...row, 'n': 'Remote edit'};
    backend.fail = true;
    await expectLater(repository.applyPullPage('alice', [remote(theirs, 3)], '3'), throwsStateError);
    expect(repository.cursor('alice'), '0');
    backend.fail = false;
    await repository.applyPullPage('alice', [remote(theirs, 3)], '3');
    expect(repository.load()['sessions'], [row]);
    expect(repository.cursor('alice'), '3');
    expect(repository.conflicts('alice'), hasLength(1));
    expect(await repository.pendingOperations('alice'), isEmpty);
    expect(repository.pendingCount('alice'), 1);
    await repository.resolveConflict('alice', 'workout', row['id'] as String, keepLocal: true);
    expect((await repository.pendingOperations('alice')).single['baseRevision'], 3);
  });

  test('remote application does not echo; tombstones and cursor survive restart', () async {
    await repository.selectNamespace('alice');
    final row = workout();
    await repository.applyPullPage('alice', [remote(row, 1)], '1');
    expect(repository.load()['sessions'], [row]);
    expect(await repository.pendingOperations('alice'), isEmpty);
    await repository.applyPullPage('alice', [remote(row, 2, deleted: true)], '2');
    final restarted = SyncRepository(backend);
    await restarted.initialize({});
    expect(restarted.load()['sessions'], isEmpty);
    expect(restarted.cursor('alice'), '2');
    await restarted.applyPullPage('alice', [remote(row, 1)], '2');
    expect(restarted.load()['sessions'], isEmpty);
  });

  test('guest adoption requires consent and late account responses remain isolated', () async {
    final row = workout();
    await repository.save({
      'sessions': [row],
      'units': 'lb',
    });
    await repository.selectNamespace('alice');
    expect(repository.load()['units'], 'lb');
    expect(await repository.pendingOperations('alice'), isEmpty);
    expect(repository.load()['sessions'], isNull);
    await repository.adoptGuest('alice');
    await repository.adoptGuest('alice');
    expect(repository.load()['sessions'], [row]);
    expect(await repository.pendingOperations('alice'), hasLength(1));
    await repository.selectNamespace('bob');
    final other = workout();
    await repository.applyPullPage('alice', [remote(other, 1)], '1');
    expect(repository.namespace, 'bob');
    expect(repository.load()['sessions'], isNull);
    expect(repository.cursor('bob'), '0');
    expect(repository.guestCounts()['workouts'], 1);
  });

  test('stale local save after pull preserves unseen remote records', () async {
    await repository.selectNamespace('alice');
    final shown = repository.load();
    final row = workout();
    await repository.applyPullPage('alice', [remote(row, 1)], '1');
    await repository.save({...shown, 'units': 'lb'});
    expect(repository.load()['sessions'], [row]);
    expect(repository.load()['units'], 'lb');
    expect(await repository.pendingOperations('alice'), isEmpty);
  });

  test('identical legacy records receive distinct repeatable occurrence identities', () {
    final row = workout()..remove('id');
    final legacy = {
      'sessions': [row, row],
    };
    final first = migrateIdentities(legacy);
    expect(first['sessions'][0]['id'], isNot(first['sessions'][1]['id']));
    expect(migrateIdentities(legacy), first);
    expect(migrateIdentities(first), first);
  });

  test('namespace creation copies harmless preferences and no personal data', () async {
    await repository.save({
      'units': 'lb',
      'profile': {'name': 'Private'},
      'bodyweight': [],
      'nutrition': {'secret': 'private'},
      'media': {'x': 'private.png'},
    });
    await repository.selectNamespace('alice');
    expect(repository.load(), {'units': 'lb'});
  });

  test('export ledger excludes imported, unknown and remote workouts', () async {
    final local = workout();
    final imported = {...workout(), 'origin': 'import'};
    final unknown = {...workout()}..remove('origin');
    await repository.save({
      'sessions': [local, imported, unknown],
    });
    expect(repository.exportableWorkouts('guest').map((e) => e['entityId']), [local['id']]);
    await repository.saveDeliveryLedger('guest', 'healthkit', {'optIn': true});
    final restarted = SyncRepository(backend);
    await restarted.initialize({});
    expect(restarted.deliveryLedger('guest', 'healthkit'), {'optIn': true});
    expect(restarted.load().containsKey('deliveries'), isFalse);
  });

  test('actual SQLite transaction failure leaves the prior snapshot intact', () async {
    final before = await sqlite.read();
    await sqlite.database.execute(
      "CREATE TRIGGER reject_commit BEFORE INSERT ON repository BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
    );
    await expectLater(
      repository.save({
        'sessions': [workout()],
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(jsonEncode(await sqlite.read()), jsonEncode(before));
  });
}
