import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/catalog/program_templates.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/models/block_program.dart';
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
  });
  tearDown(() async {
    fit.saveAndExit();
    await fit.persistNow(rethrowErrors: true);
  });

  test('hybrid selection creates exact exercises, independent enrollment and calibration work', () {
    final template = kProgramTemplates.singleWhere((p) => p.id == 'hybrid-12-week');
    expect(fit.applyTemplate(template), 5);
    final upper = fit.routines.first;
    expect(upper.program!.day, 0);
    expect(fit.exerciseById(upper.exerciseIds.first)!.name, 'Swiss Bar Bench Press');
    expect(fit.weeklyPlan.keys, containsAll([1, 2, 4, 6]));
    fit.startRoutine(upper);
    expect(fit.session!.program!.week, 1);
    expect(fit.session!.exercises.expand((e) => e.sets).where((s) => s.counts), hasLength(7));
    expect(fit.session!.exercises.first.sets.where((s) => s.counts).map((s) => s.reps), [6, 8]);
    final topIndex = fit.session!.exercises.first.sets.indexWhere((s) => s.counts);
    fit.setSessionWeight(0, topIndex, fit.fromDisplayWeight(100));
    final work = fit.session!.exercises.first.sets.where((s) => s.counts).toList();
    expect(work[1].weight, lessThan(work[0].weight));
    expect(fit.session!.exercises.first.sets.where((s) => !s.counts), hasLength(3));
    expect(
      fit.session!.exercises.first.sets.where((s) => !s.counts).map((s) => s.weight),
      everyElement(greaterThan(0)),
    );
    expect(fit.session!.exercises[1].sets.where((s) => s.counts).map((s) => s.reps), [8, 8]);
  });

  test('live prescription, limits and completed snapshot survive backup and reload', () async {
    fit.applyHybridProgram(start: DateTime(2026, 1, 5));
    final routine = fit.routines.first;
    final id = routine.exerciseIds.first;
    fit.setBlockExerciseRule(
      routine.id,
      id,
      routine.program!.rules[id]!.copyWith(seedKg: 50, maxWeightKg: 70),
    );
    fit.startRoutine(routine, on: DateTime(2026, 1, 5));
    final before = fit.session!.program!.toJson();
    await fit.persistNow(rethrowErrors: true);
    fit.saveAndExit();
    fit.loadFromStore();
    // Explicit backup restoration exercises the live-session document as well.
    fit.startRoutine(fit.routines.first, on: DateTime(2026, 1, 5));
    final backup = fit.exportJson();
    fit.resetAllData();
    expect(await fit.importJson(backup), isTrue);
    expect(fit.session!.program!.toJson(), before);
    fit.setSessionWeight(0, 3, 200); // Main work follows three warm-up sets.
    expect(fit.session!.exercises.first.sets[3].weight, 70);
    for (final e in fit.session!.exercises) {
      for (final set in e.sets) {
        set.done = true;
        set.rpe = 7;
      }
    }
    expect(await fit.finishSession(), isTrue);
    expect(fit.sessions.single.program!.programId, fit.routines.first.program!.id);
    final saved = fit.exportJson();
    fit.resetAllData();
    expect(await fit.importJson(saved), isTrue);
    expect(fit.sessions.single.program!.targets[id]!.first.weightKg, 50);
  });

  test('optional arm day redistributes calibration work and locks after starting', () {
    fit.applyHybridProgram(start: DateTime(2026, 1, 5));
    final id = fit.routines.first.program!.id;
    expect(fit.setBlockFifthDay(id, true, on: DateTime(2026, 1, 5)), isTrue);
    final counts = [
      for (final r in fit.routines)
        fit
            .blockOpening(r, on: DateTime(2026, 1, 5))
            .session
            .targets
            .values
            .fold<int>(0, (n, sets) => n + sets.length),
    ];
    expect(counts, [7, 6, 6, 7, 6]);
    fit.startRoutine(fit.routines.first, on: DateTime(2026, 1, 5));
    expect(fit.setBlockFifthDay(id, false, on: DateTime(2026, 1, 5)), isFalse);
    expect(fit.setBlockStart(id, DateTime(2026, 1, 6)), isFalse);
  });

  test('shared program imports retain methods and separate enrollment from the sender', () {
    fit.applyHybridProgram();
    final original = fit.routines.first.program!.id;
    final shared = fit.exportPlanJson(fit.routines);
    fit.resetAllData();
    final result = fit.applyPlan(parsePlan(shared));
    expect(result.routines, 5);
    expect(fit.routines.map((r) => r.program!.id).toSet(), hasLength(1));
    expect(fit.routines.first.program!.id, isNot(original));
    expect(fit.routines.first.program!.rules.values.first.method, BlockMethod.reversePyramid);
    expect(fit.exerciseById(fit.routines.first.exerciseIds.first)!.name, 'Swiss Bar Bench Press');
    final duplicate = fit.duplicateRoutine(fit.routines.first.id);
    expect(
      fit.routines.singleWhere((r) => r.id == duplicate).program!.id,
      isNot(fit.routines.first.program!.id),
    );
  });

  test('squat replacements enforce the ceiling and never inherit another machine load', () {
    fit.applyHybridProgram();
    final lower = fit.routines[1], previous = fit.routines[1].exerciseIds.first;
    fit.replaceRoutineExercise(lower.id, previous, 'qXTaZnJ');
    final rule = lower.program!.rules['qXTaZnJ']!;
    expect(rule.seedKg, 0);
    expect(fit.toDisplayWeight(rule.maxWeightKg!), greaterThan(0));
    expect(rule.maxWeightKg, closeTo(102.05828325, .000001));
    fit.setBlockExerciseRule(lower.id, 'qXTaZnJ', rule.copyWith(maxWeightKg: 200));
    fit.startRoutine(lower);
    fit.setSessionWeight(0, 0, 200);
    expect(fit.session!.exercises.first.sets.first.weight, lessThanOrEqualTo(102.05828325));
  });

  test('an unrelated parked workout is preserved when a program routine is selected', () {
    final other = fit.createRoutine('Unrelated');
    fit.toggleRoutineExercise(other, 'EIeI8Vf');
    fit.startRoutine(fit.routines.single);
    fit.parkSession();
    final parked = fit.session;
    fit.applyHybridProgram();
    fit.startRoutine(fit.routines[1]);
    expect(identical(fit.session, parked), isTrue);
  });

  test('in-workout substitutions start separately from global historical weights', () {
    fit.applyHybridProgram();
    fit.sessions.add(
      LoggedSession(DateTime(2020), 1000, [
        LoggedExercise('EIeI8Vf', 'Synthetic press', 'chest', [LoggedSet(8, 200)]),
      ]),
    );
    fit.startRoutine(fit.routines.first);
    fit.swapSessionExercise(0, 'EIeI8Vf');
    expect(fit.session!.exercises.first.sets.map((s) => s.weight), everyElement(0));
  });

  test('adding an unplanned exercise also starts with calibration rather than global history', () {
    fit.applyHybridProgram();
    fit.sessions.add(
      LoggedSession(DateTime(2020), 1000, [
        LoggedExercise('one-arm-dumbbell-row', 'Synthetic row', 'back', [LoggedSet(8, 150)]),
      ]),
    );
    fit.startRoutine(fit.routines.first);
    fit.addExerciseToSession('one-arm-dumbbell-row');
    final added = fit.session!.exercises.singleWhere((e) => e.id == 'one-arm-dumbbell-row');
    expect(added.sets.map((s) => s.weight), everyElement(0));
  });

  test('reviewing recovery preserves manual load edits before any sets are completed', () async {
    fit.applyHybridProgram();
    final r = fit.routines.first, id = fit.routines.first.exerciseIds.first;
    fit.sessions.add(
      LoggedSession(
        DateTime.now().subtract(const Duration(hours: 1)),
        1000,
        [
          LoggedExercise(id, 'Synthetic press', 'chest', [
            LoggedSet(6, 40, rpe: 7),
            LoggedSet(8, 35, rpe: 7),
          ]),
        ],
        program: BlockSession(
          programId: r.program!.id,
          day: 0,
          week: 1,
          minimumRir: 3,
          targets: {
            id: [const BlockTarget(6, 40), const BlockTarget(8, 35)],
          },
        ),
      ),
    );
    fit.startRoutine(r);
    final top = fit.session!.exercises.first.sets.indexWhere((s) => s.counts);
    fit.setSessionWeight(0, top, 60);
    final backup = fit.exportJson();
    fit.resetAllData();
    expect(await fit.importJson(backup), isTrue);
    fit.reviewBlockResponse(id, BlockResponse.stable);
    expect(fit.session!.exercises.first.sets.where((s) => s.counts).first.weight, 60);
  });

  test('established weeks preserve 60/40 volume and deloads halve the full workload', () {
    fit.applyHybridProgram(start: DateTime(2026, 1, 5));
    for (final routine in fit.routines.take(4)) {
      final targets = {
        for (final entry in routine.program!.rules.entries)
          entry.key: List.generate(
            entry.value.sets,
            (i) => BlockTarget(
              entry.value.method == BlockMethod.reversePyramid ? 6 + i * 2 : entry.value.minReps,
              50,
            ),
          ),
      };
      fit.sessions.add(
        LoggedSession(
          DateTime(2026, 1, 23),
          1800,
          [
            for (final entry in targets.entries)
              LoggedExercise(entry.key, 'Synthetic lift', 'back', [
                for (final target in entry.value) LoggedSet(target.reps, target.weightKg, rpe: 7),
              ]),
          ],
          program: BlockSession(
            programId: routine.program!.id,
            day: routine.program!.day,
            week: 3,
            minimumRir: 3,
            targets: targets,
            responses: {for (final id in targets.keys) id: BlockResponse.stable},
          ),
        ),
      );
    }
    List<int> counts(DateTime day, {bool fifth = false}) => [
      for (final r in fit.routines.take(fifth ? 5 : 4))
        fit.blockOpening(r, on: day).session.targets.values.fold<int>(0, (n, sets) => n + sets.length),
    ];
    expect(counts(DateTime(2026, 2, 2)), [12, 12, 14, 12]);
    expect(counts(DateTime(2026, 1, 26)), [7, 4, 8, 6]);
    expect(fit.setBlockFifthDay(fit.routines.first.program!.id, true, on: DateTime(2026, 2, 2)), isTrue);
    expect(counts(DateTime(2026, 2, 2), fifth: true), [12, 10, 12, 10, 6]);
  });
}
