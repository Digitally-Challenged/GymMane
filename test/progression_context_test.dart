import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/exercise_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    fit.setLanguage('en');
    fit.setUnits('kg');
  });

  String seed() {
    final ex = fit.matchExerciseByName('Barbell Bench Press')!;
    fit.sessions.add(
      LoggedSession(DateTime(2026, 10, 18), 1800, [
        LoggedExercise(ex.id, ex.name, ex.primary, [LoggedSet(8, 60, rpe: 7), LoggedSet(8, 60)]),
      ]),
    );
    return ex.id;
  }

  test('effort follows the selected scale without inventing missing effort', () {
    final id = seed();
    fit.setEffortMode('rir');
    expect(fit.lastEffortSummaryFor(id), '60×8 (RIR 3) · 60×8');
    fit.setEffortMode('rpe');
    expect(fit.lastEffortSummaryFor(id), '60×8 (RPE 7) · 60×8');
    expect(fit.lastEffortSummaryFor('unknown'), isNull);
  });

  test('advice remains separate from opt-in automatic progression', () {
    final id = seed();
    final routineId = fit.createRoutine('Trial');
    fit.toggleRoutineExercise(routineId, id);
    final routine = fit.routines.firstWhere((r) => r.id == routineId);
    expect(fit.hasProgress(id), isFalse);
    expect(fit.nextTarget(id)!.weightKg, 62.5);
    fit.startRoutine(routine);
    expect(fit.session!.exercises.single.sets.first.weight, 60);
    fit.saveAndExit();
    fit.toggleProgress(id);
    fit.startRoutine(routine);
    expect(fit.session!.exercises.single.sets.first.weight, 62.5);
  });

  testWidgets('phone context shows effort, increase reason and advice disclaimer', (tester) async {
    final id = seed();
    fit.setEffortMode('rir');
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: ExerciseContext(exerciseId: id, onHistory: () => opened = true),
            ),
          ),
        ),
      ),
    );
    expect(find.text('60×8 (RIR 3) · 60×8'), findsOneWidget);
    expect(find.textContaining(t.nextIncrease), findsOneWidget);
    expect(find.textContaining(t.nextAdvice), findsOneWidget);
    await tester.tap(find.text('60×8 (RIR 3) · 60×8'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    fit.persistNow();
  });
}
