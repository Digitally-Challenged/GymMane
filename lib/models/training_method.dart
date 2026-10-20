enum TrainingMethod {
  standard,
  linear,
  reversePyramid;

  static TrainingMethod fromJson(Object? value) =>
      values.where((m) => m.name == value).firstOrNull ?? standard;

  String get label => switch (this) {
    standard => 'Standard',
    linear => 'Linear progression',
    reversePyramid => 'Reverse pyramid',
  };

  String get description => switch (this) {
    standard => 'Use the exercise’s usual settings.',
    linear =>
      'Same load across working sets. Increase next time only after all planned reps and sets are completed; otherwise repeat the load.',
    reversePyramid =>
      'Heaviest set first, then 90% and 80% of that load. Increase next time only after all planned reps and sets are completed.',
  };
}
