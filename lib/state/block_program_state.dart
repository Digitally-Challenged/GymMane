part of 'fit_state.dart';

List<SessionSet> _unplannedBlockSets(int count, {int reps = 8}) => [
  SessionSet(8, 0, false, kind: SetKind.warmup),
  for (var i = 0; i < count; i++) SessionSet(reps, 0, false),
];

mixin BlockProgramState on FitCore, SettingsState, LibraryState, RoutinesState {
  WorkoutSession? get session;
  String? programStartError;

  int applyHybridProgram({DateTime? start}) {
    final specialtyIds = <String, String>{};
    for (final (key, name, muscle, equipment, secondary) in hybridSpecialties) {
      final existing = allExercises.where((e) => e.name == name).firstOrNull;
      specialtyIds[key] =
          existing?.id ??
          addCustomExercise(
            name: name,
            primary: muscle,
            equipment: equipment,
            secondary: secondary,
            steps: [
              'Use a comfortable setup and controlled range. Log the same loading convention each time.',
            ],
          );
    }
    final enrollment = newEntityId();
    final planWasEmpty = weeklyPlan.isEmpty;
    for (var i = 0; i < hybridDays.length; i++) {
      final (name, weekday, items) = hybridDays[i];
      final id = createRoutine(name);
      final routine = _routine(id)!;
      routine.group = '12-Week Hybrid';
      final rules = <String, BlockExerciseRule>{};
      for (final item in items) {
        final exerciseId = specialtyIds[item.$1] ?? item.$1;
        final exercise = exerciseById(exerciseId);
        if (exercise == null) throw StateError('Missing hybrid exercise: ${item.$1}');
        toggleRoutineExercise(id, exerciseId);
        routine.sets[exerciseId] = item.$2;
        final rule = hybridRule(
          item,
        ).copyWith(incrementKg: fromDisplayWeight(weightStep), roundingKg: fromDisplayWeight(weightStep));
        rules[exerciseId] = rule;
        routine.rest[exerciseId] = rule.warmupSets > 0 ? 150 : 75;
      }
      routine.program = BlockProgram(
        id: enrollment,
        start: dateOnly(start ?? DateTime.now()),
        day: i,
        rules: rules,
      );
      if (planWasEmpty && weekday > 0) weeklyPlan[weekday] = id;
    }
    setEffortMode('rir');
    _persist();
    syncTrainReminder();
    notifyListeners();
    return 5;
  }

  BlockWorkout blockOpening(Routine routine, {DateTime? on}) =>
      resolveBlockWorkout(program: routine.program!, on: on ?? DateTime.now(), history: sessions);

  String blockStatus(Routine routine, {DateTime? on}) {
    final p = routine.program;
    if (p == null) return '';
    final date = on ?? DateTime.now();
    if (dateOnly(date).isBefore(dateOnly(p.start))) return 'Starts ${p.toJson()['start']}';
    final week = p.weekOn(date);
    if (week > 12) return '12-week program complete';
    return 'Week $week / 12 · ${week % 4 == 0
        ? 'Deload'
        : week == 1
        ? 'Calibration'
        : 'Build'}';
  }

  bool setBlockFifthDay(String programId, bool enabled, {DateTime? on}) {
    final members = routines.where((r) => r.program?.id == programId).toList();
    if (members.isEmpty || !members.any((r) => r.program!.day == 4)) return false;
    final p = members.first.program!, date = on ?? DateTime.now();
    final week = p.weekOn(date);
    if (session?.program?.programId == programId && session?.complete == false) {
      return false;
    }
    if (!p.activeOn(date) ||
        week % 4 == 0 ||
        sessions.any((s) => s.program?.programId == programId && s.program?.week == week)) {
      return false;
    }
    final weeks = {...p.fifthWeeks};
    enabled ? weeks.add(week) : weeks.remove(week);
    for (final r in members) {
      r.program = r.program!.copyWith(fifthWeeks: weeks.toList()..sort());
    }
    _persist();
    notifyListeners();
    return true;
  }

  bool setBlockStart(String programId, DateTime start) {
    if (session?.program?.programId == programId && session?.complete == false) {
      return false;
    }
    if (sessions.any((s) => s.program?.programId == programId)) {
      return false;
    }
    for (final r in routines.where((r) => r.program?.id == programId)) {
      r.program = r.program!.copyWith(start: dateOnly(start), fifthWeeks: []);
    }
    _persist();
    notifyListeners();
    return true;
  }

  void setBlockExerciseRule(String routineId, String exerciseId, BlockExerciseRule rule) {
    final r = _routine(routineId);
    if (r?.program == null || !r!.program!.rules.containsKey(exerciseId)) return;
    // The same validation applies to local editing, imports and sync hydration.
    final cap = hybridSquatCap(exerciseById(exerciseId)?.name ?? '');
    final limited = cap == null ? rule : rule.copyWith(maxWeightKg: math.min(cap, rule.maxWeightKg ?? cap));
    final valid = BlockExerciseRule.fromJson(limited.toJson());
    r.program = r.program!.copyWith(rules: {...r.program!.rules, exerciseId: valid});
    _persist();
    notifyListeners();
  }
}
