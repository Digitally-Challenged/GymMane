import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/block_program.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/block_program.dart';

void main() {
  BlockProgram straight({double? cap, int day = 0, List<int> fifthWeeks = const []}) => BlockProgram(
    id: 'synthetic',
    start: DateTime(2026, 1, 5),
    day: day,
    fifthWeeks: fifthWeeks,
    rules: {
      'row': BlockExerciseRule(
        sets: 2,
        calibrationSets: 2,
        deloadSets: 1,
        minReps: 8,
        maxReps: 12,
        incrementKg: 2.5,
        roundingKg: 2.5,
        maxWeightKg: cap,
      ),
    },
  );
  LoggedSession effort(
    List<int> reps, {
    double weight = 40,
    double? rpe = 8,
    BlockResponse response = BlockResponse.stable,
    int week = 2,
    int planned = 2,
  }) => LoggedSession(
    DateTime(2026, 1, 12),
    1000,
    [
      LoggedExercise('row', 'Synthetic row', 'back', [for (final r in reps) LoggedSet(r, weight, rpe: rpe)]),
    ],
    program: BlockSession(
      programId: 'synthetic',
      day: 0,
      week: week,
      minimumRir: 2,
      targets: {'row': List.generate(planned, (_) => const BlockTarget(8, 40))},
      responses: {'row': response},
    ),
  );

  test('double progression adds reps before increasing load', () {
    final next = resolveBlockWorkout(
      program: straight(),
      on: DateTime(2026, 1, 14),
      history: [
        effort([10, 9]),
      ],
    ).session.targets['row']!;
    expect(next.map((s) => s.reps), [11, 10]);
    expect(next.map((s) => s.weightKg), [40, 40]);
    final heavier = resolveBlockWorkout(
      program: straight(),
      on: DateTime(2026, 1, 14),
      history: [
        effort([12, 12]),
      ],
    ).session.targets['row']!;
    expect(heavier.map((s) => s.weightKg), [42.5, 42.5]);
    expect(heavier.map((s) => s.reps), [8, 8]);
  });
  test('partial work, missing effort, high effort and unreviewed response hold load', () {
    for (final previous in [
      effort([12]),
      effort([12, 12], rpe: null),
      effort([12, 12], rpe: 9),
      effort([12, 12], response: BlockResponse.unreviewed),
    ]) {
      final next = resolveBlockWorkout(
        program: straight(),
        on: DateTime(2026, 1, 14),
        history: [previous],
      ).session.targets['row']!;
      expect(next.map((s) => s.weightKg), [40, 40]);
    }
  });
  test('aggravation reduces workload and load instead of earning an increase', () {
    final next = resolveBlockWorkout(
      program: straight(),
      on: DateTime(2026, 1, 14),
      history: [
        effort([12, 12], response: BlockResponse.aggravated),
      ],
    );
    expect(next.session.targets['row']!.map((s) => s.weightKg), [35]);
  });
  test('caps hold even when a completed prescription earns an increase', () {
    final next = resolveBlockWorkout(
      program: straight(cap: 40),
      on: DateTime(2026, 1, 14),
      history: [
        effort([12, 12]),
      ],
    );
    expect(next.session.targets['row']!.map((s) => s.weightKg), [40, 40]);
  });
  test('different programs and future history never seed a new enrollment', () {
    final other = straight().copyWith(start: DateTime(2026, 1, 1));
    final previous = effort([12, 12]);
    final early = resolveBlockWorkout(program: other, on: DateTime(2026, 1, 5), history: [previous]);
    expect(early.session.targets['row']!.first.weightKg, 0);
    final independent = BlockProgram(id: 'different', start: other.start, day: 0, rules: other.rules);
    expect(
      resolveBlockWorkout(
        program: independent,
        on: DateTime(2026, 1, 14),
        history: [previous],
      ).session.targets['row']!.first.weightKg,
      0,
    );
  });
  test('calendar uses date components and rejects inactive or disabled optional days', () {
    final p = straight();
    expect(p.weekOn(DateTime(2026, 1, 4, 23, 59)), 0);
    expect(p.weekOn(DateTime(2026, 1, 11, 23, 59)), 1);
    expect(p.weekOn(DateTime(2026, 1, 12)), 2);
    expect(() => resolveBlockWorkout(program: p, on: DateTime(2026, 3, 30), history: []), throwsStateError);
    expect(
      () => resolveBlockWorkout(program: straight(day: 4), on: DateTime(2026, 1, 12), history: []),
      throwsStateError,
    );
  });
  test('invalid configuration fails at the JSON boundary', () {
    final json = straight().toJson();
    expect(() => BlockProgram.fromJson({...json, 'start': '2026-02-30'}), throwsFormatException);
    final rule = straight().rules['row']!.toJson();
    for (final invalid in [
      {...rule, 'incrementKg': -1},
      {...rule, 'roundingKg': double.nan},
      {...rule, 'maxReps': 2},
      {...rule, 'calibrationSets': 3},
    ]) {
      expect(() => BlockExerciseRule.fromJson(invalid), throwsFormatException);
    }
  });

  test('a long break triggers fresh calibration instead of resuming an old load', () {
    final next = resolveBlockWorkout(
      program: straight(),
      on: DateTime(2026, 2, 5),
      history: [
        effort([12, 12]),
      ],
    );
    expect(next.session.targets['row']!.first.weightKg, 0);
    expect(next.session.minimumRir, 3);
  });
  test('earned build loads survive a reduced deload before the next block', () {
    final program = BlockProgram(
      id: 'synthetic-program',
      start: DateTime(2026, 1, 5),
      day: 0,
      rules: {
        'press': const BlockExerciseRule(
          method: BlockMethod.reversePyramid,
          sets: 3,
          calibrationSets: 2,
          deloadSets: 2,
          minReps: 6,
          maxReps: 6,
          incrementKg: 2.5,
          roundingKg: 2.5,
        ),
      },
    );
    final build = LoggedSession(
      DateTime(2026, 1, 23),
      1800,
      [
        LoggedExercise('press', 'Test press', 'chest', [
          LoggedSet(6, 100, rpe: 8),
          LoggedSet(8, 90, rpe: 8),
          LoggedSet(10, 80, rpe: 8),
        ]),
      ],
      program: BlockSession(
        programId: program.id,
        day: 0,
        week: 3,
        minimumRir: 2,
        targets: {
          'press': [const BlockTarget(6, 100), const BlockTarget(8, 90), const BlockTarget(10, 80)],
        },
        responses: {'press': BlockResponse.stable},
      ),
    );
    final deload = LoggedSession(
      DateTime(2026, 1, 30),
      900,
      [
        LoggedExercise('press', 'Test press', 'chest', [LoggedSet(6, 90, rpe: 6), LoggedSet(8, 80, rpe: 6)]),
      ],
      program: BlockSession(
        programId: program.id,
        day: 0,
        week: 4,
        minimumRir: 4,
        targets: {
          'press': [const BlockTarget(6, 90), const BlockTarget(8, 80)],
        },
      ),
    );
    final opening = resolveBlockWorkout(program: program, on: DateTime(2026, 2, 2), history: [deload, build]);
    expect(opening.session.week, 5);
    expect(opening.session.targets['press']!.map((s) => s.weightKg), [102.5, 90, 80]);
  });
}
