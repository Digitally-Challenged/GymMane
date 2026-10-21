import 'dart:convert';
import 'dart:io';

// Run from backend/: dart tests/date-compatibility.dart
// The same fixture strings pass through real HTTP push/pull in sync.test.ts.
void main() {
  final fixtures = jsonDecode(File('tests/fixtures/workout-dates.json').readAsStringSync()) as List<dynamic>;
  for (final fixture in fixtures) {
    final timestamp = fixture['timestamp'] as String;
    final parsed = DateTime.parse(timestamp);
    if (parsed.toIso8601String() != fixture['dartIso']) {
      throw StateError('Dart round-trip mismatch: $timestamp');
    }
  }
  stdout.writeln('Dart parsed and round-tripped ${fixtures.length} sync fixtures');
}
