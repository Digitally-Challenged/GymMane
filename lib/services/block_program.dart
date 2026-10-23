import 'dart:math' as math;

import '../models/block_program.dart';
import '../models/workout.dart';
import 'training_program.dart';

class BlockWorkout {
  const BlockWorkout(this.session, this.plans);
  final BlockSession session;
  final Map<String, List<PlannedSet>> plans;
}

/// Resolve from tagged, durable history only. Deloads cannot become build baselines.
BlockWorkout resolveBlockWorkout({
  required BlockProgram program,
  required DateTime on,
  required List<LoggedSession> history,
}) {
  if (!program.activeOn(on)) throw StateError('Program is outside its 12-week window');
  final week = program.weekOn(on);
  final deload = week % 4 == 0;
  final fifth = program.fifthOn(week);
  if (program.day == 4 && !fifth) throw StateError('Optional arm day is not enabled this week');
  final builds =
      history
          .where(
            (s) =>
                s.program?.programId == program.id &&
                s.program?.day == program.day &&
                !s.program!.deload &&
                !s.date.isAfter(on),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  final activity =
      history
          .where(
            (s) => s.program?.programId == program.id && s.program?.day == program.day && !s.date.isAfter(on),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  final reentry = activity.isNotEmpty && on.difference(activity.first.date).inDays > 14;
  if (reentry) {
    builds.clear();
  }
  final last = builds.firstOrNull;
  final counts = <String, int>{};
  for (final entry in program.rules.entries) {
    final rule = entry.value;
    final before = last?.program?.targets[entry.key]?.length;
    final movedBefore = last != null && program.fifthOn(last.program!.week) ? rule.optionalMove : 0;
    final normalCount = before == null ? rule.calibrationSets : before + movedBefore;
    counts[entry.key] = math.max(0, math.min(rule.sets, normalCount) - (fifth ? rule.optionalMove : 0));
  }
  // Add at most one set per routine/build week, never on post-deload resumption.
  if (!deload &&
      last != null &&
      last.program!.week < week &&
      week % 4 != 1 &&
      last.program!.targets.keys.every((id) => blockExercisePassed(last, id))) {
    for (final entry in program.rules.entries) {
      final max = entry.value.sets - (fifth ? entry.value.optionalMove : 0);
      if (counts[entry.key]! < max) {
        counts[entry.key] = counts[entry.key]! + 1;
        break;
      }
    }
  }
  final targets = <String, List<BlockTarget>>{};
  final reasons = <String, String>{};
  final plans = <String, List<PlannedSet>>{};
  for (final entry in program.rules.entries) {
    final id = entry.key, rule = entry.value;
    final recent = builds.where((s) => s.program!.targets.containsKey(id)).firstOrNull;
    final prior = recent?.program?.targets[id] ?? const <BlockTarget>[];
    final logged = recent?.exercises.where((e) => e.id == id).firstOrNull?.workingSets ?? const <LoggedSet>[];
    final before = prior.length;
    var count = counts[id]!;
    final increasedSets = before > 0 && count > before;
    if (deload) count = math.min(rule.deloadSets, (count / 2).round());
    if (count == 0) continue;
    final response = recent?.program?.responses[id] ?? BlockResponse.unreviewed;
    final passed = recent != null && blockExercisePassed(recent, id) && !increasedSets;
    var base = logged.firstOrNull?.weight ?? prior.firstOrNull?.weightKg ?? (reentry ? 0 : rule.seedKg);
    var reason = recent == null
        ? 'Calibrate a comfortable load; keep 3–4 reps in reserve.'
        : response == BlockResponse.aggravated
        ? 'Reduce load and volume after an aggravated response.'
        : response == BlockResponse.unreviewed
        ? 'Hold load until the previous response is reviewed.'
        : increasedSets
        ? 'One extra set; hold load while volume increases.'
        : 'Hold load and build repetitions within the range.';
    final complete = before > 0 && logged.length == before;
    final effort =
        complete &&
        logged.every(
          (s) =>
              s.rpe != null &&
              s.rpe!.isFinite &&
              s.rpe! >= 0 &&
              s.rpe! <= 10 - math.max(rule.minimumRir, recent!.program!.minimumRir),
        );
    var bump = false;
    if (rule.method == BlockMethod.reversePyramid) {
      bump = passed && effort && before == rule.sets;
    } else {
      bump = passed && effort && logged.every((s) => s.reps >= rule.maxReps);
    }
    if (bump && base > 0 && !deload) {
      final candidate = _bounded(base + rule.incrementKg, rule);
      if (candidate > _bounded(base, rule) + .001) {
        base = candidate;
        reason = 'Targets, effort and recovery met; increase by one load step.';
      } else {
        bump = false;
        reason = 'Hold load; the available step or load cap prevents an increase.';
      }
    }
    if (recent != null && response == BlockResponse.stable && !effort) {
      reason = 'Hold load; log the required reserve on every working set.';
    }
    if (response == BlockResponse.aggravated) {
      base *= .9;
      count = math.max(1, count - 1);
    }
    if (deload) {
      // Use actual build loads, never an unperformed earned increase.
      base = (logged.firstOrNull?.weight ?? prior.firstOrNull?.weightKg ?? (reentry ? 0 : rule.seedKg)) * .9;
      reason = 'Deload: reduced work, at least four reps in reserve; build baseline preserved.';
    }
    base = _bounded(base, rule);
    if (rule.maxWeightKg != null && base >= rule.maxWeightKg! - .001 && !deload) {
      reason = 'Load cap reached; track clean repetitions and consistent range.';
    }
    final work = <BlockTarget>[];
    for (var i = 0; i < count; i++) {
      final old = i < logged.length ? logged[i] : null;
      final reps = rule.method == BlockMethod.reversePyramid
          ? rule.minReps + i * 2
          : !bump && !deload && passed && old != null
          ? math.min(rule.maxReps, math.max(rule.minReps, old.reps + 1))
          : !bump && old != null
          ? old.reps.clamp(rule.minReps, rule.maxReps)
          : rule.minReps;
      final weight = rule.method == BlockMethod.reversePyramid
          ? pyramidWeight(base, i, rule.roundingKg)
          : _bounded(
              old != null && !bump && !deload && response != BlockResponse.aggravated ? old.weight : base,
              rule,
            );
      work.add(BlockTarget(reps, weight));
    }
    targets[id] = List.unmodifiable(work);
    reasons[id] = reason;
    plans[id] = [
      for (var i = 0; i < rule.warmupSets; i++)
        PlannedSet(
          reps: i == 0
              ? 8
              : i == 1
              ? 5
              : 3,
          kind: SetKind.warmup,
          weightKg: _bounded(base * (.4 + .2 * i), rule),
        ),
      for (final set in work) PlannedSet(reps: set.reps, weightKg: set.weightKg),
    ];
  }
  return BlockWorkout(
    BlockSession(
      programId: program.id,
      day: program.day,
      week: week,
      minimumRir: deload ? 4 : (week == 1 || builds.isEmpty ? 3 : 2),
      targets: targets,
      reasons: reasons,
      rules: program.rules,
    ),
    plans,
  );
}

bool blockExercisePassed(LoggedSession session, String id) {
  final snapshot = session.program;
  final targets = snapshot?.targets[id];
  if (snapshot == null ||
      snapshot.deload ||
      targets == null ||
      targets.isEmpty ||
      snapshot.responses[id] != BlockResponse.stable) {
    return false;
  }
  final sets = session.exercises.where((e) => e.id == id).firstOrNull?.workingSets;
  if (sets == null || sets.length != targets.length) return false;
  for (var i = 0; i < sets.length; i++) {
    final s = sets[i], target = targets[i];
    if (s.kind == SetKind.failure ||
        s.kind == SetKind.restPause ||
        !s.weight.isFinite ||
        s.weight <= 0 ||
        s.weight + .001 < target.weightKg ||
        s.reps < target.reps ||
        s.rpe == null ||
        !s.rpe!.isFinite ||
        s.rpe! < 0 ||
        s.rpe! > 10 - math.max(snapshot.minimumRir, snapshot.rules[id]?.minimumRir ?? 2)) {
      return false;
    }
  }
  return true;
}

double _bounded(double weight, BlockExerciseRule rule) {
  final capped = math.min(rule.maxWeightKg ?? 1000, math.max(0.0, weight));
  return double.parse(((capped / rule.roundingKg + 1e-9).floor() * rule.roundingKg).toStringAsFixed(6));
}
