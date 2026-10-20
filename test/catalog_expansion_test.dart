import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/catalog/arsenal_machines.dart';
import 'package:gymmane/catalog/arsenal_reloaded.dart';
import 'package:gymmane/catalog/equipment_aliases.dart';
import 'package:gymmane/catalog/exercise_catalog.dart';
import 'package:gymmane/catalog/free_weight_expansion.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/services/exercise_match.dart';
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
  });

  test('existing exercise identities and movement data survive expansion', () {
    for (final original in kCoreExercises) {
      final current = kExercises.singleWhere((e) => e.id == original.id);
      expect(current.name, original.name);
      expect(current.primary, original.primary);
      expect(current.secondary, original.secondary);
      expect(current.equipment, original.equipment);
      expect(current.steps, original.steps);
      expect(current.art, original.art);
    }
    expect(kExercises.first.id, 'EIeI8Vf');
    expect(kExercises.length, kCoreExercises.length + 101);
  });

  test('Arsenal machine histories have distinct IDs and combo movements', () {
    final arsenal = [...kArsenalMachines, ...kArsenalReloaded];
    expect(arsenal, hasLength(73));
    expect(arsenal.every((e) => e.id.startsWith('arsenal-')), isTrue);
    expect(
      arsenal.where((e) => e.art.isEmpty).map((e) => e.name),
      isEmpty,
      reason: 'Every Arsenal movement must have matching artwork, not a placeholder.',
    );
    for (final id in ['arsenal-reloaded-leg-extension', 'arsenal-reloaded-pendulum-squat']) {
      expect(arsenal.singleWhere((e) => e.id == id).art, id);
    }
    for (final query in [
      'Arsenal Reloaded Pendulum Squat',
      'Arsenal Reloaded Leg Extension',
      'Arsenal Reloaded Seated Leg Curl',
      'Arsenal M-1 Hip Adduction',
      'Arsenal M-1 Hip Abduction',
      'Arsenal FORGE-X Wide Chest Press',
    ]) {
      expect(arsenal.where((e) => e.name == query), hasLength(1), reason: query);
    }
  });

  test('equipment names and free-weight aliases are searchable', () {
    for (final query in [
      'Arsenal',
      'Reloaded',
      'M1',
      'FORGE-X',
      'Bayesian',
      'db floor press',
      'bb spoto press',
    ]) {
      expect(kExercises.where(exerciseSearch(query)), isNotEmpty, reason: query);
    }
    for (final name in kEquipmentAliases.keys) {
      expect(kCoreExercises.where((e) => e.name == name), hasLength(1), reason: name);
    }
    final cable = kExercises.where(exerciseSearch('Arsenal M-1 Functional Trainer'));
    expect(cable.length, greaterThan(20));
    expect(cable.every((e) => e.equipment == 'Cable'), isTrue);
    expect(kExercises.where(exerciseSearch('Arsenal Alpha Olympic Flat Bench')).single.id, 'EIeI8Vf');
  });

  test('new entries fall back to their English names in other languages', () {
    fit.setLanguage('es');
    for (final exercise in [...kArsenalMachines, ...kArsenalReloaded, ...kFreeWeightExpansion]) {
      expect(t.catalogName(exercise.id, exercise.name), exercise.name);
      expect(t.catalogSteps(exercise.id, exercise.steps), exercise.steps);
    }
  });

  test('new machine can be selected in a routine and survives backup restore', () {
    const id = 'arsenal-reloaded-pendulum-squat';
    final routineId = fit.createRoutine('Arsenal legs');
    fit.toggleRoutineExercise(routineId, id);
    final backup = fit.exportJson();
    fit.resetAllData();
    expect(fit.importJson(backup), isTrue);
    final routine = fit.routines.singleWhere((r) => r.id == routineId);
    fit.startRoutine(routine);
    expect(fit.session!.exercises.single.id, id);
    expect(fit.exerciseById(id)!.name, 'Arsenal Reloaded Pendulum Squat');
    fit.saveAndExit();
  });
}
