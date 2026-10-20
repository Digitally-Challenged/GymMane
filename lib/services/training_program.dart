import 'dart:math' as math;

import '../models/training_method.dart';
import '../models/workout.dart';

/// Resolve automatic routine targets without changing the saved prescription.
/// Explicit weights remain fixed; only automatic weights follow progression.
List<PlannedSet> programOpeningPlan({
  required TrainingMethod method,
  required List<PlannedSet> plan,
  required List<LoggedSet> previous,
  required double fallbackWeightKg,
  required double incrementKg,
  required double roundingKg,
}) {
  if (method == TrainingMethod.standard || plan.isEmpty) return plan;
  final work = plan.where((p) => p.kind != SetKind.warmup).toList();
  final last = previous.where((p) => p.counts).toList();
  if (work.isEmpty) return plan;
  final base = last.isEmpty ? fallbackWeightKg : last.first.weight;
  final top = base.isFinite && base > 0 ? base : 0.0;
  final grid = roundingKg.isFinite && roundingKg > 0 ? roundingKg : 2.5;
  double weightAt(double load, int index) =>
      method == TrainingMethod.reversePyramid ? pyramidWeight(load, index, grid) : load;
  final hit =
      last.length == work.length &&
      top > 0 &&
      List.generate(work.length, (i) => i).every(
        (i) =>
            work[i].reps != null &&
            work[i].reps! > 0 &&
            last[i].reps >= work[i].reps! &&
            last[i].weight + 0.001 >= (work[i].weightKg ?? weightAt(top, i)),
      );
  final bump = hit && incrementKg.isFinite && incrementKg > 0 ? incrementKg : 0.0;
  // A fixed top-set weight anchors reverse-pyramid back-off sets too.
  final next = work.first.weightKg ?? (top + bump);
  var index = 0;
  PlannedSet workingSet(PlannedSet p) {
    final weight = weightAt(next, index++);
    return p.copyWith(weightKg: p.weightKg ?? weight);
  }

  return [
    for (final p in plan)
      if (p.kind == SetKind.warmup)
        p.copyWith(weightKg: p.weightKg ?? (next * .5 / grid).floor() * grid)
      else
        workingSet(p),
  ];
}

/// Back-off loads use a percentage of the top set, rounded down to loadable steps.
double pyramidWeight(double top, int index, double grid) {
  if (index == 0) return top;
  final fraction = math.max(0.1, 1 - index * 0.1);
  return double.parse((((top * fraction / grid) + 1e-9).floor() * grid).toStringAsFixed(3));
}
