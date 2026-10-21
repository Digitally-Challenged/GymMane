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
