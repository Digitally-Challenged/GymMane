import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/catalog/exercise_catalog.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pushUp = 'I4hDWkc';
  const diamond = 'x6KpKpq';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.setUnits('kg');
    fit.autoAdvance = false;
  });

  tearDown(() {
    if (fit.session != null) fit.saveAndExit();
  });

  Routine routineWith(List<String> ids) {
    final id = fit.createRoutine('Calistenia');
    for (final ex in ids) {
      fit.toggleRoutineExercise(id, ex);
    }
    return fit.routines.firstWhere((r) => r.id == id);
  }

  Future<void> workout(Routine r, int reps, {int sets = 3}) async {
    fit.startRoutine(r);
    fit.endCountdown();
    final ex = fit.session!.exercises.first;
    expect(ex.sets.length, greaterThanOrEqualTo(sets));
    for (var i = 0; i < sets; i++) {
      fit.setSessionReps(0, i, reps);
      fit.toggleSet(0, i);
    }
    await fit.finishSession();
  }

  test('las cadenas no repiten ejercicios y todos existen', () async {
    final all = [for (final c in kProgressions) ...c];
    expect(all.toSet().length, all.length);
    for (final id in all) {
      expect(fit.exerciseById(id), isNotNull, reason: id);
    }
    expect(nextStepOf(pushUp), diamond);
    expect(nextStepOf('pseudo-planche-push-up'), isNull);
  });

  test('un solo buen día no basta: hacen falta dos entrenos seguidos', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNull);
    fit.saveAndExit();
    await workout(r, 9);
    expect(fit.summaryLevelUp?.to.id, diamond);
  });

  test('si una de las veces no llega a 3×8 no se sugiere', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 7);
    expect(fit.summaryLevelUp, isNull);
  });

  test('las negativas suben con 3×5', () async {
    final r = routineWith(['negative-pull-up']);
    await workout(r, 5);
    fit.saveAndExit();
    await workout(r, 5);
    expect(fit.summaryLevelUp?.to.id, 'lBDjFxJ');
  });

  test('cambiarlo en la rutina lo pone en el mismo sitio con sus series', () async {
    final r = routineWith([pushUp, '6YUfHPL']);
    fit.bumpRoutineSets(r.id, pushUp, 1);
    final sets = fit.routineSets(r, pushUp);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.levelUpInRoutine, isTrue);
    expect(fit.levelUpSwap(), 'Calistenia');
    expect(r.exerciseIds, [diamond, '6YUfHPL']);
    expect(fit.routineSets(r, diamond), sets);
    expect(fit.summaryLevelUp, isNull);
  });

  test('después de verlo no vuelve a salir en una semana', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNotNull);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNull);
  });

  test('borrar el entreno que la sacó la deja volver a salir', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNotNull);
    fit.saveAndExit();
    fit.deleteSession(fit.sessions.last);
    await workout(r, 8);
    expect(fit.summaryLevelUp?.to.id, diamond);
  });

  test('borrar otro entreno no la vuelve a sacar', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNotNull);
    fit.saveAndExit();
    fit.deleteSession(fit.sessions.first);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNull);
  });

  test('«Me quedo con este» lo silencia para siempre y se puede deshacer', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    final undo = fit.levelUpStay()!;
    expect(fit.levelStay, contains(pushUp));
    undo();
    expect(fit.levelStay, isNot(contains(pushUp)));
    expect(fit.summaryLevelUp?.to.id, diamond);
  });

  test('seguir entrenando no gasta la sugerencia', () async {
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNotNull);
    fit.continueSession();
    expect(fit.summaryLevelUp, isNull);
    await fit.finishSession();
    expect(fit.summaryLevelUp?.to.id, diamond);
  });

  test('con el ajuste apagado nunca sale', () async {
    fit.toggleLevelHints();
    final r = routineWith([pushUp]);
    await workout(r, 8);
    fit.saveAndExit();
    await workout(r, 8);
    expect(fit.summaryLevelUp, isNull);
  });

  test('se guarda y vuelve con la copia', () async {
    fit.levelStay.add(pushUp);
    fit.levelSeen['negative-dip'] = 123;
    fit.toggleLevelHints();
    final saved = fit.toJson();
    fit.resetAllData();
    fit.applyBackup(saved);
    expect(fit.levelStay, {pushUp});
    expect(fit.levelSeen['negative-dip'], 123);
    expect(fit.levelHints, isFalse);
  });
}
