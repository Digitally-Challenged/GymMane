import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/catalog/program_templates.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/models/training_method.dart';
import 'package:gymmane/services/plan_share.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.setLanguage('en');
    fit.setUnits('kg');
    fit.setWeightStep(2.5);
  });
  tearDown(() {
    if (fit.session != null) fit.saveAndExit();
  });

  test('5×5 template starts five sets of five, with a single deadlift set', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'stronglifts'));
    fit.startRoutine(fit.routines.first);
    expect(fit.session!.exercises.first.sets.map((s) => s.reps), [5, 5, 5, 5, 5]);
    fit.saveAndExit();
    final b = fit.routines.last;
    final deadlift = b.exerciseIds.last;
    expect(fit.plannedSets(b, deadlift).single.reps, 5);
  });
  void previous(Routine r, List<LoggedSet> sets) {
    final id = r.exerciseIds.first;
    final ex = fit.exerciseById(id)!;
    fit.sessions.add(
      LoggedSession(DateTime(2026, 10, 19), 1200, [
        LoggedExercise(id, ex.name, ex.primary, sets),
      ], routineId: r.id),
    );
  }

  test('linear progression increases only after every prescribed set hits its target', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'linear'));
    final r = fit.routines.first;
    previous(r, [LoggedSet(5, 100), LoggedSet(5, 100), LoggedSet(5, 100)]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [102.5, 102.5, 102.5]);
    fit.saveAndExit();
    fit.sessions.clear();
    previous(r, [LoggedSet(4, 100), LoggedSet(4, 100), LoggedSet(4, 100)]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [100, 100, 100]);
    expect(fit.session!.exercises.first.sets.map((s) => s.reps), [5, 5, 5]);
  });

  test('reverse pyramid holds after a missed back-off set and reduces load 10 percent each set', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'reverse-pyramid'));
    final r = fit.routines.first;
    previous(r, [LoggedSet(6, 100), LoggedSet(8, 90), LoggedSet(9, 80)]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.map((s) => s.reps), [6, 8, 10]);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [100, 90, 80]);
  });

  test('editing the reverse-pyramid top load updates untouched back-off sets', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'reverse-pyramid'));
    fit.startRoutine(fit.routines.first);
    fit.setSessionWeight(0, 0, 100);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [100, 90, 80]);
    fit.setSessionWeight(0, 1, 85); // Keep a deliberate adjustment.
    fit.setSessionWeight(0, 0, 110);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [110, 85, 87.5]);
  });

  test('routine backup, duplication and plan sharing retain progression behavior', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'linear'));
    final r = fit.routines.first;
    final copied = fit.duplicateRoutine(r.id);
    final shared = fit.exportPlanJson([r]);
    final backup = fit.exportJson();
    fit.resetAllData();
    expect(fit.importJson(backup), isTrue);
    final restored = fit.routines.singleWhere((r) => r.id == copied);
    previous(restored, [LoggedSet(5, 100), LoggedSet(5, 100), LoggedSet(5, 100)]);
    fit.startRoutine(restored);
    expect(fit.session!.exercises.first.sets.first.weight, 102.5);
    fit.saveAndExit();
    fit.resetAllData();
    fit.applyPlan(parsePlan(shared));
    final imported = fit.routines.first;
    previous(imported, [LoggedSet(5, 100), LoggedSet(5, 100), LoggedSet(5, 100)]);
    fit.startRoutine(imported);
    expect(fit.session!.exercises.first.sets.first.weight, 102.5);
  });

  test('5×5 progress carries from A to B within the same program', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'stronglifts'));
    previous(fit.routines.first, List.generate(5, (_) => LoggedSet(5, 60)));
    fit.startRoutine(fit.routines.last);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), List.filled(5, 62.5));
  });

  test('partial sessions do not advance and warm-ups do not count toward completion', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'linear'));
    final r = fit.routines.first;
    previous(r, [LoggedSet(5, 100), LoggedSet(5, 100)]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.first.weight, 100);
    fit.saveAndExit();
    fit.sessions.clear();
    previous(r, [
      LoggedSet(10, 20, kind: SetKind.warmup),
      LoggedSet(5, 100),
      LoggedSet(5, 100),
      LoggedSet(5, 100),
    ]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.first.weight, 102.5);
  });

  test('reverse pyramid increases after 6/8/10 and retains fixed-weight overrides', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'reverse-pyramid'));
    final r = fit.routines.first;
    previous(r, [LoggedSet(6, 100), LoggedSet(8, 90), LoggedSet(10, 80)]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [102.5, 90, 80]);
    fit.saveAndExit();
    fit.setPlannedSets(r.id, r.exerciseIds.first, [
      const PlannedSet(reps: 6, weightKg: 110),
      const PlannedSet(reps: 8, weightKg: 85),
      const PlannedSet(reps: 10),
    ]);
    fit.startRoutine(r);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [110, 85, 87.5]);
    fit.setSessionWeight(0, 0, 112.5);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [112.5, 85, 90]);
  });

  test('back-off adjustment does not carry the top load into a matching back-off weight', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'reverse-pyramid'));
    fit.startRoutine(fit.routines.first);
    fit.setSessionWeight(0, 0, 100);
    fit.setSessionWeight(0, 0, 112.5);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [112.5, 100, 90]);
  });

  test('old and unknown routine methods preserve standard behavior', () {
    for (final method in [null, 'future-method', 42]) {
      final r = Routine.fromJson({'id': 'old', 'n': 'Old', 'ex': [], 'method': method});
      expect(r.method, TrainingMethod.standard);
    }
  });
  test('progression uses pounds and respects an exercise-specific increment', () {
    fit.setUnits('lb');
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'linear'));
    final r = fit.routines.first;
    final w = fit.fromDisplayWeight(100);
    previous(r, [LoggedSet(5, w), LoggedSet(5, w), LoggedSet(5, w)]);
    fit.startRoutine(r);
    expect(fit.toDisplayWeight(fit.session!.exercises.first.sets.first.weight), closeTo(105, .01));
    fit.saveAndExit();
    fit.progressStep[r.exerciseIds.first] = fit.fromDisplayWeight(2.5);
    fit.startRoutine(r);
    expect(fit.toDisplayWeight(fit.session!.exercises.first.sets.first.weight), closeTo(102.5, .01));
  });

  test('RPT manual edits preserve completed back-off sets', () {
    fit.applyTemplate(kProgramTemplates.singleWhere((p) => p.id == 'reverse-pyramid'));
    fit.startRoutine(fit.routines.first);
    fit.setSessionWeight(0, 0, 100);
    fit.session!.exercises.first.sets[1].done = true;
    fit.setSessionWeight(0, 0, 110);
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), [110, 90, 87.5]);
  });
}
