import 'dart:convert';
import '../../catalog/exercise_catalog.dart';
import '../../models/exercise.dart';
import '../../models/workout.dart';

/// Embed only referenced dependencies, keeping old documents/backups portable.
/// Definitions stay within the document's account, never the global catalog.
void hydrateRoutineDependencies(Map<String, dynamic> document) {
  final custom = <String, Exercise>{};
  final builtinIds = kExercises.map((e) => e.id).toSet();
  for (final row in (document['custom'] as List?) ?? []) {
    final exercise = Exercise.fromJson((row as Map).cast<String, dynamic>());
    if (builtinIds.contains(exercise.id)) {
      throw const FormatException('Custom exercise overrides a built-in');
    }
    final previous = custom[exercise.id];
    if (previous != null && jsonEncode(previous.toJson()) != jsonEncode(exercise.toJson())) {
      throw const FormatException('Conflicting custom exercise definitions');
    }
    custom[exercise.id] = exercise;
  }
  final routines = [
    for (final row in (document['routines'] as List?) ?? [])
      Routine.fromJson((row as Map).cast<String, dynamic>()),
  ];
  for (final routine in routines) {
    for (final entry in routine.exerciseDefinitions.entries) {
      final previous = custom[entry.key];
      if (previous != null && jsonEncode(previous.toJson()) != jsonEncode(entry.value.toJson())) {
        throw const FormatException('Conflicting custom exercise definitions');
      }
      custom[entry.key] = entry.value;
    }
  }
  for (final routine in routines) {
    for (final id in routine.exerciseIds) {
      if (custom[id] case final exercise?) routine.exerciseDefinitions[id] = exercise;
    }
  }
  if (document.containsKey('routines')) {
    document['routines'] = routines.map((r) => r.toJson()).toList();
  }
}

bool _sameExercise(Exercise? left, Exercise? right) =>
    jsonEncode(left?.toJson()) == jsonEncode(right?.toJson());

/// Reconcile a newer revision against its previous wire payload, not a device's
/// retained library copy. The document is a consistent account-local projection;
/// wire payloads remain unchanged in the entity ledger and operation receipts.
/// Null stages a user conflict without changing the document. A new entity with
/// independently colliding definitions still fails validation atomically.
Map<String, dynamic>? reconcileRemoteRoutineDependencies(
  Map<String, dynamic> document,
  Map<String, dynamic> incoming, {
  Map<String, dynamic>? previous,
  Set<String> pendingRoutineIds = const {},
  bool acceptRemote = false,
}) {
  final routine = Routine.fromJson(incoming);
  final prior = previous == null ? null : Routine.fromJson(previous);
  final routines = [
    for (final row in (document['routines'] as List?) ?? [])
      Routine.fromJson((row as Map).cast<String, dynamic>()),
  ];
  final custom = [
    for (final row in (document['custom'] as List?) ?? [])
      Exercise.fromJson((row as Map).cast<String, dynamic>()),
  ];
  final current = <String, Exercise>{
    for (final r in routines) ...r.exerciseDefinitions,
    for (final exercise in custom) exercise.id: exercise,
  };
  final replacements = <String, Exercise>{};
  for (final entry in routine.exerciseDefinitions.entries) {
    final existing = current[entry.key];
    if (existing == null || _sameExercise(existing, entry.value)) continue;
    final old = prior?.exerciseDefinitions[entry.key];
    if (!acceptRemote && _sameExercise(old, entry.value)) {
      // A routine-only edit carrying an older dependency is not a reversal of
      // an exercise edit already observed through another referencing routine.
      routine.exerciseDefinitions[entry.key] = existing;
      continue;
    }
    if (!acceptRemote) {
      if (old == null) throw const FormatException('Conflicting custom exercise definitions');
      if (!_sameExercise(existing, old)) return null;
      if (routines.any(
        (r) => r.id != routine.id && pendingRoutineIds.contains(r.id) && r.exerciseIds.contains(entry.key),
      )) {
        return null;
      }
    }
    replacements[entry.key] = entry.value;
  }
  if (replacements.isNotEmpty) {
    if (document.containsKey('custom')) {
      document['custom'] = [for (final e in custom) (replacements[e.id] ?? e).toJson()];
    }
    for (final r in routines) {
      for (final id in r.exerciseIds) {
        if (replacements[id] case final exercise?) r.exerciseDefinitions[id] = exercise;
      }
    }
    document['routines'] = routines.map((r) => r.toJson()).toList();
  }
  return routine.toJson();
}
