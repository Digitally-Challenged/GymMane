import '../models/training_method.dart';

class ProgramDay {
  const ProgramDay(this.name, this.exercises, {this.weekday});

  final String name;
  final List<(String, int)> exercises;
  final int? weekday;
}

class ProgramTemplate {
  const ProgramTemplate(
    this.id,
    this.name,
    this.days, {
    this.targetReps = const [],
    this.method = TrainingMethod.standard,
    this.description,
    this.restSeconds,
  });

  final String id;
  final String name;
  final List<ProgramDay> days;
  final List<int> targetReps;
  final TrainingMethod method;
  final String? description;
  final int? restSeconds;
}

const List<ProgramTemplate> kProgramTemplates = [
  ProgramTemplate('fullbody', 'Full Body', [
    ProgramDay('Full Body', [
      ('Barbell Squat', 3),
      ('Barbell Bench Press', 3),
      ('Barbell Row', 3),
      ('Overhead Press', 3),
      ('Romanian Deadlift', 3),
      ('Plank', 3),
    ], weekday: 1),
    ProgramDay('Full Body', [
      ('Barbell Squat', 3),
      ('Barbell Bench Press', 3),
      ('Barbell Row', 3),
      ('Overhead Press', 3),
      ('Romanian Deadlift', 3),
      ('Plank', 3),
    ], weekday: 3),
    ProgramDay('Full Body', [
      ('Barbell Squat', 3),
      ('Barbell Bench Press', 3),
      ('Barbell Row', 3),
      ('Overhead Press', 3),
      ('Romanian Deadlift', 3),
      ('Plank', 3),
    ], weekday: 5),
  ]),
  ProgramTemplate('ppl', 'Push Pull Legs', [
    ProgramDay('Push', [
      ('Barbell Bench Press', 4),
      ('Incline Dumbbell Press', 3),
      ('Overhead Press', 3),
      ('Lateral Raise', 3),
      ('Triceps Pushdown', 3),
    ], weekday: 1),
    ProgramDay('Pull', [
      ('Pull Up', 4),
      ('Barbell Row', 4),
      ('Lat Pulldown', 3),
      ('Face Pull', 3),
      ('Barbell Curl', 3),
    ], weekday: 3),
    ProgramDay('Legs', [
      ('Barbell Squat', 4),
      ('Romanian Deadlift', 3),
      ('Leg Press', 3),
      ('Leg Curl', 3),
      ('Standing Calf Raise', 4),
    ], weekday: 5),
  ]),
  ProgramTemplate('upperlower', 'Upper Lower', [
    ProgramDay('Upper', [
      ('Barbell Bench Press', 4),
      ('Barbell Row', 4),
      ('Overhead Press', 3),
      ('Lat Pulldown', 3),
      ('Barbell Curl', 3),
      ('Triceps Pushdown', 3),
    ], weekday: 1),
    ProgramDay('Lower', [
      ('Barbell Squat', 4),
      ('Romanian Deadlift', 3),
      ('Leg Press', 3),
      ('Leg Curl', 3),
      ('Standing Calf Raise', 4),
    ], weekday: 2),
    ProgramDay('Upper', [
      ('Incline Dumbbell Press', 4),
      ('Pull Up', 4),
      ('Dumbbell Standing Overhead Press', 3),
      ('Seated Cable Row', 3),
      ('Hammer Curl', 3),
      ('Triceps Dip', 3),
    ], weekday: 4),
    ProgramDay('Lower', [
      ('Deadlift', 3),
      ('Front Squat', 3),
      ('Leg Extension', 3),
      ('Leg Curl', 3),
      ('Standing Calf Raise', 4),
    ], weekday: 5),
  ]),
  ProgramTemplate('abcd', 'ABCD Split', [
    ProgramDay('A · Chest & Triceps', [
      ('Barbell Bench Press', 4),
      ('Incline Dumbbell Press', 3),
      ('Cable Fly', 3),
      ('Triceps Pushdown', 3),
      ('Skull Crushers', 3),
    ], weekday: 1),
    ProgramDay('B · Back & Biceps', [
      ('Pull Up', 4),
      ('Barbell Row', 4),
      ('Lat Pulldown', 3),
      ('Barbell Curl', 3),
      ('Hammer Curl', 3),
    ], weekday: 2),
    ProgramDay('C · Legs', [
      ('Barbell Squat', 4),
      ('Romanian Deadlift', 3),
      ('Leg Press', 3),
      ('Leg Curl', 3),
      ('Standing Calf Raise', 4),
    ], weekday: 4),
    ProgramDay('D · Shoulders & Abs', [
      ('Overhead Press', 4),
      ('Lateral Raise', 3),
      ('Face Pull', 3),
      ('Hanging Leg Raise', 3),
      ('Plank', 3),
    ], weekday: 5),
  ]),
  ProgramTemplate('abcde', 'ABCDE Split', [
    ProgramDay('A · Chest', [
      ('Barbell Bench Press', 4),
      ('Incline Dumbbell Press', 4),
      ('Cable Fly', 3),
      ('Triceps Dip', 3),
    ], weekday: 1),
    ProgramDay('B · Back', [
      ('Deadlift', 3),
      ('Pull Up', 4),
      ('Barbell Row', 4),
      ('Seated Cable Row', 3),
    ], weekday: 2),
    ProgramDay('C · Legs', [
      ('Barbell Squat', 4),
      ('Leg Press', 4),
      ('Leg Extension', 3),
      ('Leg Curl', 3),
      ('Standing Calf Raise', 4),
    ], weekday: 3),
    ProgramDay('D · Shoulders', [
      ('Overhead Press', 4),
      ('Dumbbell Standing Overhead Press', 3),
      ('Lateral Raise', 4),
      ('Face Pull', 3),
    ], weekday: 4),
    ProgramDay('E · Arms', [
      ('Barbell Curl', 4),
      ('Skull Crushers', 4),
      ('Hammer Curl', 3),
      ('Triceps Pushdown', 3),
    ], weekday: 5),
  ]),
  ProgramTemplate(
    'stronglifts',
    'StrongLifts 5×5',
    [
      ProgramDay('Workout A', [
        ('Barbell Squat', 5),
        ('Barbell Bench Press', 5),
        ('Barbell Row', 5),
      ], weekday: 1),
      ProgramDay('Workout B', [('Barbell Squat', 5), ('Overhead Press', 5), ('Deadlift', 1)], weekday: 3),
    ],
    targetReps: [5],
    method: TrainingMethod.linear,
    restSeconds: 180,
    description:
        'A/B workouts: 5×5, deadlift 1×5. Rest 3 minutes. Add weight only when every prescribed set reaches five reps. Edit the schedule or use routine rotation to alternate A/B.',
  ),
  ProgramTemplate(
    'linear',
    'Linear Progression · 3×5',
    [
      ProgramDay('Linear A', [
        ('Barbell Squat', 3),
        ('Barbell Bench Press', 3),
        ('Barbell Row', 3),
      ], weekday: 1),
      ProgramDay('Linear B', [('Barbell Squat', 3), ('Overhead Press', 3), ('Deadlift', 1)], weekday: 3),
    ],
    targetReps: [5],
    method: TrainingMethod.linear,
    restSeconds: 180,
    description:
        'A/B workouts: 3×5, deadlift 1×5. Rest 3 minutes. Increase after all targets are met; repeat the load after missed reps. Schedule and weights are editable.',
  ),
  ProgramTemplate(
    'reverse-pyramid',
    'Reverse Pyramid · 6/8/10',
    [
      ProgramDay('Reverse Pyramid Upper', [
        ('Barbell Bench Press', 3),
        ('Barbell Row', 3),
        ('Overhead Press', 3),
      ], weekday: 2),
      ProgramDay('Reverse Pyramid Lower', [
        ('Barbell Squat', 3),
        ('Romanian Deadlift', 3),
        ('Standing Calf Raise', 3),
      ], weekday: 5),
    ],
    targetReps: [6, 8, 10],
    method: TrainingMethod.reversePyramid,
    restSeconds: 180,
    description:
        'Upper/lower workouts: 6, 8, then 10 reps at 100%, 90%, and 80% load, rounded down to your weight step. Rest 3 minutes. Increase only after all three targets are met.',
  ),
  ProgramTemplate('startingstrength', 'Starting Strength', [
    ProgramDay('Workout A', [('Barbell Squat', 3), ('Barbell Bench Press', 3), ('Deadlift', 1)], weekday: 1),
    ProgramDay('Workout B', [('Barbell Squat', 3), ('Overhead Press', 3), ('Barbell Row', 3)], weekday: 3),
  ]),
  ProgramTemplate('rr', 'Recommended Routine', [
    ProgramDay('Recommended Routine', [
      ('Negative Pull-up', 3),
      ('Bodyweight Squat', 3),
      ('Negative Dip', 3),
      ('Bodyweight Romanian Deadlift', 3),
      ('Incline Row', 3),
      ('Incline Push-up', 3),
      ('Plank', 3),
      ('Banded Pallof Press', 3),
      ('Reverse Hyperextension', 3),
    ], weekday: 1),
    ProgramDay('Recommended Routine', [
      ('Negative Pull-up', 3),
      ('Bodyweight Squat', 3),
      ('Negative Dip', 3),
      ('Bodyweight Romanian Deadlift', 3),
      ('Incline Row', 3),
      ('Incline Push-up', 3),
      ('Plank', 3),
      ('Banded Pallof Press', 3),
      ('Reverse Hyperextension', 3),
    ], weekday: 3),
    ProgramDay('Recommended Routine', [
      ('Negative Pull-up', 3),
      ('Bodyweight Squat', 3),
      ('Negative Dip', 3),
      ('Bodyweight Romanian Deadlift', 3),
      ('Incline Row', 3),
      ('Incline Push-up', 3),
      ('Plank', 3),
      ('Banded Pallof Press', 3),
      ('Reverse Hyperextension', 3),
    ], weekday: 5),
  ]),
  ProgramTemplate('home', 'No Kit', [
    ProgramDay('Home A', [('Push Up', 3), ('Pull Up', 3), ('Bodyweight Squat', 3), ('Plank', 3)], weekday: 2),
    ProgramDay('Home B', [
      ('Triceps Dip', 3),
      ('Chin Up', 3),
      ('Lunge', 3),
      ('Hanging Leg Raise', 3),
    ], weekday: 5),
  ]),
  ProgramTemplate(
    'hybrid-12-week',
    '12-Week Hybrid',
    [
      ProgramDay('Upper A', [], weekday: 1),
      ProgramDay('Lower A', [], weekday: 2),
      ProgramDay('Upper B', [], weekday: 4),
      ProgramDay('Lower B', [], weekday: 6),
    ],
    description:
        'Four core days, optional arms day. Calibrate loads, build repetitions and weight, and deload every fourth week. Upper/lower volume: 60/40.',
  ),
];
