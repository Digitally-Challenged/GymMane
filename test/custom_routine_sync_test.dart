import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/persistence/storage_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/catalog/exercise_catalog.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/models/exercise.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/sync/store_sync_repository.dart';
import 'package:gymmane/state/fit_state.dart';

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
    await fit.persistNow(rethrowErrors: true);
  });

  test('guest custom routine survives adoption and delivery to a fresh device', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final customId = fit.addCustomExercise(
      name: 'Custom hold',
      primary: 'abdomen',
      equipment: 'Bodyweight',
      mode: 'time',
    );
    final routineId = fit.createRoutine('Portable');
    final builtinId = kExercises.first.id;
    fit.toggleRoutineExercise(routineId, builtinId);
    fit.toggleRoutineExercise(routineId, customId);
    await fit.persistNow(rethrowErrors: true);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    final adopted = fit.routines.single;
    expect(fit.routineExercises(adopted).map((e) => e.id), [builtinId, customId]);
    expect(fit.modeOf(customId), 'time');
    expect(fit.isRepsOnly(customId), isTrue);
    fit.startRoutine(adopted);
    expect(fit.session!.exercises.map((e) => e.id), [builtinId, customId]);
    fit.saveAndExit();
    final operation = (await adapter.pendingOperations('alice')).single;

    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.loadFromStore();
    final fresh = StoreSyncRepository(Store.instance);
    await fresh.selectNamespace('alice');
    await fresh.applyPullPage('alice', [
      {
        'entityType': 'routine',
        'entityId': routineId,
        'revision': 1,
        'deleted': false,
        'payload': operation['payload'],
        'cursor': '1',
      },
    ], '1');
    expect(fit.routineExercises(fit.routines.single).map((e) => e.id), [builtinId, customId]);
    expect(fit.modeOf(customId), 'time');
    expect(fit.isRepsOnly(customId), isTrue);
    fit.startRoutine(fit.routines.single);
    expect(fit.session!.exercises.map((e) => e.id), [builtinId, customId]);
  });

  test('legacy backups hydrate referenced definitions and adoption/pull are idempotent', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final customId = fit.addCustomExercise(
      name: 'Custom bike',
      primary: 'quads',
      equipment: 'Machine',
      mode: 'cardio',
    );
    final unused = fit.addCustomExercise(name: 'Unused', primary: 'chest', equipment: 'Bodyweight');
    final routineId = fit.createRoutine('Legacy');
    fit.toggleRoutineExercise(routineId, customId);
    final legacy = fit.toJson();
    for (final row in legacy['routines'] as List) {
      row.remove('exerciseDefinitions');
    }
    await fit.restoreBackup(legacy);
    expect(fit.modeOf(customId), 'cardio');
    expect(fit.routineExercises(fit.routines.single).single.id, customId);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    await adapter.adoptGuest('alice');
    final operations = await adapter.pendingOperations('alice');
    expect(operations, hasLength(1));
    final payload = operations.single['payload'] as Map<String, dynamic>;
    expect((payload['exerciseDefinitions'] as Map).keys, [customId]);
    expect((payload['exerciseDefinitions'] as Map).containsKey(unused), isFalse);
    await adapter.selectNamespace('bob');
    final remote = <String, dynamic>{
      'entityType': 'routine',
      'entityId': routineId,
      'revision': 1,
      'deleted': false,
      'payload': payload,
      'cursor': '1',
    };
    await adapter.applyPullPage('bob', [remote], '1');
    await adapter.applyPullPage('bob', [remote], '1');
    expect(fit.routines, hasLength(1));
    expect(fit.modeOf(customId), 'cardio');
    expect(fit.routineSets(fit.routines.single, customId), 1);
    expect(await adapter.pendingCount('bob'), 0);
  });

  test('missing legacy dependencies block start with actionable IDs', () {
    final routine = Routine('missing-routine', 'Missing', [kExercises.first.id, 'missing-custom']);
    fit.routines.add(routine);
    fit.startRoutine(routine);
    expect(fit.session, isNull);
    expect(fit.routineStartError, isA<MissingRoutineExercises>());
    expect(fit.missingRoutineExerciseIds(routine), ['missing-custom']);
    expect(fit.routineStartError.toString(), contains('Restore or remove'));
    expect(fit.routineExercises(routine), isEmpty);
    expect(fit.resolveRoutineExercises(routine).canStart, isFalse);
  });

  test('remote custom deletion removes the dependency without resurrection', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final id = fit.addCustomExercise(name: 'Pushups', primary: 'chest', equipment: 'Bodyweight');
    final routineId = fit.createRoutine('Delete');
    fit.toggleRoutineExercise(routineId, id);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    expect(fit.isCustom(id), isTrue);
    fit.deleteCustomExercise(id);
    await fit.persistNow(rethrowErrors: true);
    expect(fit.exerciseById(id), isNull);
    expect(fit.routines.single.exerciseIds, isEmpty);
    expect(fit.routines.single.toJson().containsKey('exerciseDefinitions'), isFalse);
    fit.loadFromStore();
    expect(fit.exerciseById(id), isNull);
    await adapter.selectNamespace('guest');
    expect(fit.exerciseById(id), isNotNull);
    expect(fit.routines.single.exerciseIds, [id]);
  });

  test('malformed pull pages and definition collisions preserve data and cursor', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final id = fit.addCustomExercise(name: 'Original', primary: 'chest', equipment: 'Bodyweight');
    final routineId = fit.createRoutine('Original');
    fit.toggleRoutineExercise(routineId, kExercises.first.id);
    fit.toggleRoutineExercise(routineId, id);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    final payload = (await adapter.pendingOperations('alice')).single['payload'] as Map<String, dynamic>;
    await adapter.selectNamespace('bob');
    final original = <String, dynamic>{
      'entityType': 'routine',
      'entityId': routineId,
      'revision': 1,
      'deleted': false,
      'payload': payload,
      'cursor': '1',
    };
    await adapter.applyPullPage('bob', [original], '1');
    final before = Store.instance.load();
    final definitions = payload['exerciseDefinitions'] as Map;
    for (final invalid in [
      {
        id: {...definitions[id] as Map, 'id': 'different'},
      },
      {
        id: {
          ...definitions[id] as Map,
          'st': [3],
        },
      },
      {
        kExercises.first.id: {...definitions[id] as Map, 'id': kExercises.first.id},
      },
    ]) {
      final malformed = {...payload, 'exerciseDefinitions': invalid};
      await expectLater(
        adapter.applyPullPage('bob', [
          {
            ...original,
            'entityId': '22222222-2222-4222-8222-222222222222',
            'payload': {...payload, 'id': '22222222-2222-4222-8222-222222222222'},
            'cursor': '2',
          },
          {...original, 'revision': 2, 'payload': malformed, 'cursor': '2'},
        ], '2'),
        throwsFormatException,
      );
      expect(Store.instance.load(), before);
      expect(await adapter.cursor('bob'), '1');
    }
    final conflicting = Routine(
      '11111111-1111-4111-8111-111111111111',
      'Collision',
      [id],
      exerciseDefinitions: {
        id: Exercise.fromJson({...definitions[id] as Map<String, dynamic>, 'n': 'Conflicting'}),
      },
    );
    await expectLater(
      adapter.applyPullPage('bob', [
        {...original, 'entityId': conflicting.id, 'payload': conflicting.toJson(), 'cursor': '2'},
      ], '2'),
      throwsFormatException,
    );
    expect(Store.instance.load(), before);
    expect(await adapter.cursor('bob'), '1');
    // A response for Alice while Bob is active cannot alter Bob's definitions.
    final aliceEdit = {
      ...payload,
      'n': 'Alice edited',
      'exerciseDefinitions': {
        id: {...definitions[id] as Map, 'n': 'Alice definition'},
      },
    };
    await adapter.applyPullPage('charlie', [
      {...original, 'revision': 3, 'payload': aliceEdit, 'cursor': '3'},
    ], '3');
    expect(fit.routines.single.name, 'Original');
    expect(fit.exerciseById(id)!.name, 'Original');
    expect(Store.instance.load(), before);
  });

  test('duplicating a synced routine retains dependencies after source deletion', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final id = fit.addCustomExercise(
      name: 'Imported',
      primary: 'chest',
      equipment: 'Bodyweight',
      mode: 'time',
    );
    final source = fit.createRoutine('Source');
    fit.toggleRoutineExercise(source, id);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    final copy = fit.duplicateRoutine(source);
    fit.deleteRoutine(source);
    final duplicated = fit.routines.singleWhere((r) => r.id == copy);
    expect(fit.routineExercises(duplicated).single.id, id);
    fit.setSecondary(id, ['triceps']);
    expect(fit.exerciseById(id)!.secondary, ['triceps']);
    fit.updateCustomExercise(
      id,
      name: 'Edited',
      primary: 'chest',
      equipment: 'Bodyweight',
      difficulty: 'Beginner',
      steps: ['Move'],
      mode: 'cardio',
    );
    expect(fit.routineExercises(duplicated).single.name, 'Edited');
    expect(fit.modeOf(id), 'cardio');
    await fit.persistNow(rethrowErrors: true);
    fit.loadFromStore();
    expect(fit.routineExercises(fit.routines.single).single.name, 'Edited');
  });

  test('conflicting guest definitions cannot overwrite an existing account custom exercise', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final id = fit.addCustomExercise(name: 'Guest original', primary: 'chest', equipment: 'Bodyweight');
    final guestExercise = fit.customExercises.single;
    final routine = fit.createRoutine('Guest');
    fit.toggleRoutineExercise(routine, id);
    await adapter.selectNamespace('alice');
    fit.customExercises.add(guestExercise.copyWith(name: 'Account original'));
    await fit.persistNow(rethrowErrors: true);
    final before = Store.instance.load();
    await expectLater(adapter.adoptGuest('alice'), throwsFormatException);
    expect(Store.instance.load(), before);
    expect(fit.exerciseById(id)!.name, 'Account original');
    expect(fit.routines, isEmpty);
    await adapter.selectNamespace('guest');
    expect(fit.exerciseById(id)!.name, 'Guest original');
    expect(fit.routines.single.id, routine);
  });

  test('malformed backup dependency preserves the original state', () async {
    final id = fit.addCustomExercise(name: 'Original', primary: 'chest', equipment: 'Bodyweight');
    final routine = fit.createRoutine('Original');
    fit.toggleRoutineExercise(routine, id);
    await fit.persistNow(rethrowErrors: true);
    final before = Store.instance.load();
    final backup = jsonDecode(jsonEncode(fit.toJson())) as Map<String, dynamic>;
    backup['profile']['name'] = 'Should not apply';
    backup['routines'][0]['exerciseDefinitions'][id]['k'] = 'unsupported';
    await expectLater(fit.restoreBackup(backup), throwsFormatException);
    expect(Store.instance.load(), before);
    expect(fit.routines.single.name, 'Original');
  });

  test('stored pre-definition account routines upgrade durably and only once', () async {
    final adapter = StoreSyncRepository(Store.instance);
    final id = fit.addCustomExercise(
      name: 'Legacy hold',
      primary: 'abdomen',
      equipment: 'Bodyweight',
      mode: 'time',
    );
    final custom = fit.customExercises.single.toJson();
    final routineId = fit.createRoutine('Stored legacy');
    fit.toggleRoutineExercise(routineId, id);
    await adapter.selectNamespace('alice');
    await adapter.adoptGuest('alice');
    await fit.persistNow(rethrowErrors: true);
    // Emulate the durable v1 format written before dependency definitions existed.
    final prefs = await SharedPreferences.getInstance();
    final snapshot = jsonDecode(prefs.getString(PreferencesBackend.key)!) as Map<String, dynamic>;
    final account = snapshot['namespaces']['alice'];
    account['document']['custom'] = [custom];
    account['document']['routines'][0].remove('exerciseDefinitions');
    account['entities']['routine:$routineId']['payload'].remove('exerciseDefinitions');
    account['outbox'] = [];
    await prefs.setString(PreferencesBackend.key, jsonEncode(snapshot));
    await Store.instance.init();
    fit.loadFromStore();
    final upgraded = (await Store.instance.repository.pendingOperations('alice')).single;
    expect(upgraded['payload']['exerciseDefinitions'][id]['k'], 'time');
    expect(fit.routines.single.exerciseDefinitions[id]!.mode, 'time');
    await Store.instance.init();
    fit.loadFromStore();
    expect(await Store.instance.repository.pendingOperations('alice'), [upgraded]);
  });
}
