import 'dart:convert';
import '../../models/identity.dart';
import '../../models/workout.dart';

/// Pure and repeatable: preserve old backups and never alter catalog IDs.
Map<String, dynamic> migrateIdentities(Map<String, dynamic> source) {
  final data = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  String routineId(String old) => old.isEmpty || isEntityId(old) ? old : legacyEntityId('routine', old);
  final routines = (data['routines'] as List?) ?? [];
  final seen = <String>{};
  for (final raw in routines) {
    final r = raw as Map<String, dynamic>;
    r['id'] = routineId(r['id'] as String);
    if (!seen.add(r['id'] as String)) throw const FormatException('Duplicate routine identity');
    Routine.fromJson(r);
  }
  seen.clear();
  final occurrences = <String, int>{};
  for (final raw in (data['sessions'] as List?) ?? []) {
    final s = raw as Map<String, dynamic>;
    if (s['id'] == null) {
      final base = legacyEntityId('workout', s);
      final occurrence = occurrences.update(base, (n) => n + 1, ifAbsent: () => 0);
      s['id'] = occurrence == 0 ? base : legacyEntityId('workout-occurrence', [base, occurrence]);
    }
    if (!isEntityId(s['id']) || !seen.add(s['id'] as String)) {
      throw const FormatException('Invalid or duplicate workout identity');
    }
    if (s['r'] != null) s['r'] = routineId(s['r'] as String);
    LoggedSession.fromJson(s);
  }
  for (final key in ['weeklyPlan']) {
    final map = data[key] as Map?;
    if (map != null) data[key] = map.map((k, v) => MapEntry(k, routineId(v as String)));
  }
  for (final key in ['planExtras', 'planMoves']) {
    final map = data[key] as Map?;
    if (map != null) {
      data[key] = map.map((k, v) => MapEntry(k, (v as List).map((id) => routineId(id as String)).toList()));
    }
  }
  if (data['rotationIds'] case final List ids) {
    data['rotationIds'] = ids.map((id) => routineId(id as String)).toList();
  }
  if (data['rotationNext'] case final String id) data['rotationNext'] = routineId(id);
  if (data['live'] case final Map live) {
    if (live['r'] case final String id) live['r'] = routineId(id);
  }
  return data;
}
