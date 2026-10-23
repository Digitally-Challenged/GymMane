import '../models/block_program.dart';

/// Exact catalog IDs; specialty bars/row variants are embedded custom definitions.
const hybridDays = [
  (
    'Upper A',
    1,
    [
      ('swiss', 3, 2, 2, 6, 6, 0),
      ('chest-row-dual', 3, 2, 2, 8, 12, 0),
      ('goJ6ezq', 2, 1, 1, 12, 20, 0),
      ('slDvUAU', 2, 1, 1, 10, 15, 0),
      ('3ZflifB', 2, 1, 1, 10, 15, 0),
    ],
  ),
  (
    'Lower A',
    2,
    [
      ('arsenal-reloaded-pendulum-squat', 3, 2, 2, 8, 12, 0),
      ('arsenal-reloaded-power-squat', 2, 1, 0, 8, 12, 0),
      ('arsenal-reloaded-seated-leg-curl', 3, 2, 1, 10, 15, 0),
      ('arsenal-reloaded-seated-calf-raise', 2, 1, 1, 12, 20, 0),
      ('G08RZcQ', 1, 1, 0, 10, 15, 1),
      ('3ZflifB', 1, 1, 0, 10, 15, 1),
    ],
  ),
  (
    'Upper B',
    4,
    [
      ('arsenal-reloaded-iso-incline-press', 3, 2, 2, 8, 12, 0),
      ('close-grip-lat-pulldown', 3, 2, 2, 8, 12, 0),
      ('one-arm-dumbbell-row', 2, 1, 1, 8, 12, 0),
      ('goJ6ezq', 2, 1, 1, 12, 20, 0),
      ('G08RZcQ', 2, 1, 1, 10, 15, 1),
      ('3ZflifB', 2, 1, 1, 10, 15, 1),
    ],
  ),
  (
    'Lower B',
    6,
    [
      ('trap-bar-deadlift', 3, 2, 2, 6, 6, 0),
      ('arsenal-reloaded-linear-hack-squat', 3, 2, 2, 8, 12, 0),
      ('arsenal-reloaded-seated-leg-curl', 2, 2, 1, 10, 15, 0),
      ('arsenal-reloaded-seated-calf-raise', 2, 1, 1, 12, 20, 0),
      ('G08RZcQ', 1, 1, 0, 10, 15, 1),
      ('3ZflifB', 1, 1, 0, 10, 15, 1),
    ],
  ),
  ('Optional Arms', 0, [('G08RZcQ', 3, 3, 0, 10, 15, 0), ('3ZflifB', 3, 3, 0, 10, 15, 0)]),
];

BlockExerciseRule hybridRule((String, int, int, int, int, int, int) item) {
  final (id, sets, initial, deload, low, high, move) = item;
  final rpt = id == 'swiss' || id == 'trap-bar-deadlift';
  final squat = id.contains('squat');
  final compound = rpt || squat || low == 8;
  return BlockExerciseRule(
    method: rpt ? BlockMethod.reversePyramid : BlockMethod.doubleProgression,
    sets: sets,
    calibrationSets: initial,
    deloadSets: deload,
    minReps: low,
    maxReps: high,
    minimumRir: squat ? 3 : 2,
    warmupSets: rpt || id.contains('pendulum')
        ? 3
        : compound
        ? 1
        : 0,
    optionalMove: move,
  );
}

const hybridSpecialties = [
  ('swiss', 'Swiss Bar Bench Press', 'chest', 'Barbell', ['triceps']),
  ('chest-row-dual', 'Arsenal Chest Row (Dual Arm)', 'back', 'Machine', ['biceps']),
  ('chest-row-single', 'Arsenal Chest Row (Single Arm)', 'back', 'Machine', ['biceps']),
];

double? hybridSquatCap(String name) =>
    name.toLowerCase().contains('barbell') && name.toLowerCase().contains('squat') ? 102.05828325 : null;
