import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/backup_zip.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/workout_import.dart';
import 'package:gymmane/services/media_store.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RejectingBackend implements StorageBackend {
  RejectingBackend(this.inner);
  final StorageBackend inner;
  bool reject = false;
  Completer<void>? entered;
  Completer<void>? release;
  @override
  Future<Map<String, dynamic>?> read() => inner.read();
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (entered != null) {
      final gate = release!;
      entered!.complete();
      entered = null;
      await gate.future;
    }
    if (reject) throw StateError('Injected disk full');
    return inner.write(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late RejectingBackend backend;
  final bytes = Uint8List.fromList([1, 2, 3]);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Store.backendFactory = (prefs) async => backend = RejectingBackend(PreferencesBackend(prefs));
    await Store.instance.init();
    dir = await Directory.systemTemp.createTemp('restore_safety');
    MediaStore.directory = dir.path;
    fit.resetAllData();
    await fit.persistNow(rethrowErrors: true);
  });
  tearDown(() async {
    backend.reject = false;
    fit.saveAndExit();
    await fit.persistNow();
    MediaStore.directory = null;
    await dir.delete(recursive: true);
    Store.backendFactory = (prefs) async => PreferencesBackend(prefs);
  });
  Future<String> originalMedia() async {
    final file = await MediaStore.saveBytes('original', 'png', bytes);
    fit.exerciseMedia['exercise'] = file!;
    fit.updateProfile(name: 'Original');
    await fit.persistNow(rethrowErrors: true);
    return file;
  }

  Uint8List zip(Map<String, dynamic> document) {
    final archive = Archive()..addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(document)));
    return ZipEncoder().encodeBytes(archive);
  }

  test('late malformed backup field cannot mutate early profile or original media', () async {
    final original = await originalMedia();
    final before = fit.toJson();
    expect(
      await restoreBackupZip(
        zip({
          ...before,
          'profile': {'name': 'Wrong'},
          'sessions': [
            {'d': 'not a date', 'ex': []},
          ],
        }),
      ),
      isFalse,
    );
    expect(fit.toJson(), before);
    expect(await MediaStore.readBytes(original), bytes);
    expect(
      await fit.importJson(
        jsonEncode({
          ...before,
          'steps': {'goal': 'invalid'},
        }),
      ),
      isFalse,
    );
    expect(fit.toJson(), before);
  });

  test('commit failure cleans staged files and preserves memory, durable data and originals', () async {
    final original = await originalMedia();
    final backup = await buildBackupZip();
    fit.updateProfile(name: 'Current');
    await fit.persistNow(rethrowErrors: true);
    final before = fit.toJson();
    final stored = Store.instance.load();
    final files = dir.listSync().map((f) => f.path).toList()..sort();
    backend.reject = true;
    expect(await restoreBackupZip(backup), isFalse);
    expect(fit.toJson(), before);
    expect(Store.instance.load(), stored);
    expect(dir.listSync().map((f) => f.path).toList()..sort(), files);
    expect(await MediaStore.readBytes(original), bytes);
    expect(Store.instance.saveFailed.value, isTrue);
  });

  test('media staging failure never starts data replacement', () async {
    await originalMedia();
    final backup = await buildBackupZip();
    fit.updateProfile(name: 'Current');
    final before = fit.toJson();
    MediaStore.directory = null;
    expect(await restoreBackupZip(backup), isFalse);
    expect(fit.toJson(), before);
  });

  test('repeated legacy restore preserves migrated identities and schedule references', () async {
    final legacy = {
      'routines': [
        {'id': 'r-old', 'n': 'Push', 'ex': []},
      ],
      'weeklyPlan': {'1': 'r-old'},
      'sessions': [
        {'d': '2026-01-01T12:00:00.000', 'dur': 120, 'r': 'r-old', 'ex': []},
      ],
    };
    await fit.restoreBackup(legacy);
    final id = fit.sessions.single.id;
    final routine = fit.routines.single.id;
    await fit.restoreBackup(legacy);
    expect(fit.sessions.single.id, id);
    expect(fit.routines.single.id, routine);
    expect(fit.sessions.single.routineId, routine);
    expect(fit.weeklyPlan[1], routine);
    expect(Store.instance.load()['sessions'][0]['id'], id);
  });

  test('repeated external import is stable and distinct set content is not discarded', () async {
    final ex = fit.allExercises.first;
    ParsedSession parsed(double weight) =>
        ParsedSession(DateTime(2026, 1, 1), 120)
          ..exercises.add(ParsedExercise(ex.name, ex.primary, id: ex.id)..sets.add(ParsedSet(8, weight)));
    expect(fit.importParsedSessions([parsed(30)]), 1);
    final id = fit.sessions.single.id;
    expect(fit.sessions.single.origin, 'import');
    expect(fit.importParsedSessions([parsed(30)]), 0);
    expect(fit.sessions.single.id, id);
    expect(fit.importParsedSessions([parsed(40)]), 1);
    expect(fit.sessions.map((s) => s.id).toSet(), hasLength(2));
    fit.sessions.clear();
    expect(fit.importParsedSessions([parsed(30)]), 1);
    expect(fit.sessions.single.id, id);
    await fit.persistNow(rethrowErrors: true);
  });

  test('account reset and media deletion preserve another namespace files', () async {
    final original = await originalMedia();
    await Store.instance.repository.selectNamespace('alice');
    fit.loadFromStore();
    fit.resetAllData();
    await fit.persistNow(rethrowErrors: true);
    await MediaStore.delete(original);
    expect(await MediaStore.readBytes(original), bytes);
    await Store.instance.repository.selectNamespace('guest');
    fit.loadFromStore();
    expect(fit.exerciseMedia['exercise'], original);
    expect(await MediaStore.readBytes(original), bytes);
  });

  test('corrupt legacy read refuses initialization and cannot overwrite original bytes', () async {
    SharedPreferences.setMockInitialValues({'gymmane_v1': '{corrupt'});
    await expectLater(Store.instance.init(), throwsFormatException);
    await expectLater(Store.instance.save({'sessions': []}), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString('gymmane_v1'), '{corrupt');
    // Restore the test store so cleanup is independent of the rejected read.
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
  });

  test('UI edit while pull awaits disk is preserved and becomes an explicit conflict', () async {
    final repo = Store.instance.repository;
    await repo.selectNamespace('alice');
    fit.loadFromStore();
    final ex = fit.allExercises.first;
    final row = LoggedSession(DateTime.now(), 120, [
      LoggedExercise(ex.id, ex.name, ex.primary, [LoggedSet(8, 30)]),
    ], name: 'Original');
    fit.sessions.add(row);
    await fit.persistNow(rethrowErrors: true);
    final op = (await repo.pendingOperations('alice')).single;
    Map<String, dynamic> entity(int revision, String name) => {
      'entityType': 'workout',
      'entityId': row.id,
      'revision': revision,
      'deleted': false,
      'payload': {...row.toJson(), 'n': name},
      'cursor': '$revision',
    };
    await repo.applyPushResults('alice', [
      {'operationId': op['operationId'], 'status': 'accepted', 'entity': entity(1, 'Original')},
    ]);
    final entered = Completer<void>(), release = Completer<void>();
    final syncing = fit.applySyncChange(() {
      backend.entered = entered;
      backend.release = release;
      return repo.applyPullPage('alice', [entity(2, 'Remote')], '2');
    });
    await entered.future;
    fit.renameSession(row, 'Local during disk write');
    release.complete();
    await syncing;
    expect(fit.sessions.single.name, 'Local during disk write');
    expect(repo.conflicts('alice')['workout:${row.id}']['payload']['n'], 'Remote');
    expect(await repo.pendingOperations('alice'), isEmpty);
  });

  test('failed workout completion never reports success and retry commits one identity', () async {
    final ex = fit.allExercises.first;
    fit.sessionPicks.add(ex.id);
    fit.startSession();
    fit.toggleSet(0, 0);
    await fit.persistNow(rethrowErrors: true);
    backend.reject = true;
    final finishing = fit.finishSession();
    expect(fit.isSessionFinishing, isTrue);
    expect(fit.isSessionComplete, isFalse);
    expect(await finishing, isFalse);
    final id = fit.session!.workoutId;
    expect(fit.session!.complete, isFalse);
    expect(fit.sessions, isEmpty);
    expect(fit.session!.exercises.first.sets.first.done, isTrue);
    expect(Store.instance.saveFailed.value, isTrue);
    backend.reject = false;
    expect(await fit.finishSession(), isTrue);
    expect(fit.isSessionComplete, isTrue);
    expect(fit.sessions.single.id, id);
    expect(Store.instance.load()['sessions'][0]['id'], id);
  });

  test('editing and continuing a completed workout keeps its ID without a delete operation', () async {
    final ex = fit.allExercises.first;
    final logged = LoggedSession(DateTime.now(), 120, [
      LoggedExercise(ex.id, ex.name, ex.primary, [LoggedSet(8, 30)]),
    ]);
    fit.sessions.add(logged);
    await fit.persistNow();
    fit.resumeLoggedSession(logged);
    expect(fit.sessions.single.id, logged.id);
    await fit.finishSession();
    expect(fit.sessions.single.id, logged.id);
    fit.continueSession();
    expect(fit.sessions.single.id, logged.id);
    await fit.finishSession();
    expect(fit.sessions.single.id, logged.id);
    expect(Store.instance.load()['sessions'][0]['id'], logged.id);
  });
}
