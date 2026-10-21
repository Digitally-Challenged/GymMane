import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workout.dart';
import 'persistence/backend_factory.dart';
import 'persistence/storage_backend.dart';
import 'persistence/sync_repository.dart';

class Store {
  Store._();
  static final Store instance = Store._();

  static const _key = 'gymmane_v1';
  SharedPreferences? _prefs;
  final _saveFailed = ValueNotifier(false);
  ValueListenable<bool> get saveFailed => _saveFailed;

  static Future<StorageBackend> Function(SharedPreferences) backendFactory = openStorageBackend;
  SyncRepository? _repository;
  bool _initializationFailed = false;
  SyncRepository get repository => _repository ?? (throw StateError('Store is not initialized'));

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final backend = await backendFactory(_prefs!);
      final repo = SyncRepository(backend);
      final existing = await backend.read();
      final raw = existing == null ? _prefs!.getString(_key) : null;
      final legacy = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      await repo.initialize(legacy);
      _repository = repo;
      _initializationFailed = false;
    } catch (_) {
      _initializationFailed = true;
      _saveFailed.value = true;
      rethrow;
    }
  }

  Map<String, dynamic> load() => _repository?.load() ?? {};

  Set<String> protectedFileNames() => _repository?.fileNamesOutsideActiveNamespace() ?? {};

  String? note(String key) => _prefs?.getString('gm_$key');

  void setNote(String key, String value) => _prefs?.setString('gm_$key', value);

  Future<void> save(Map<String, dynamic> data, {bool replace = false}) async {
    try {
      // Some previews instantiate state before startup initializes storage.
      if (_initializationFailed) throw StateError('Storage initialization failed; original data preserved');
      if (_repository == null) return;
      await repository.save((finite(data) as Map).cast<String, dynamic>(), replace: replace);
      _saveFailed.value = false;
    } catch (_) {
      _saveFailed.value = true;
      rethrow;
    }
  }

  static Object? finite(Object? v) => switch (v) {
    double d when !d.isFinite => 0.0,
    Map m => {for (final e in m.entries) '${e.key}': finite(e.value)},
    List l => [for (final x in l) finite(x)],
    _ => v,
  };

  String exportJson(Map<String, dynamic> data) => const JsonEncoder.withIndent('  ').convert(finite(data));

  String exportCsv(List<LoggedSession> sessions) {
    final rows = StringBuffer(
      'date,exercise,muscle,set,reps,weight_kg,volume_kg,est_1rm_kg,distance_km,duration_s,rpe\n',
    );
    final ordered = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    for (final s in ordered) {
      final day = s.date.toIso8601String().split('T').first;
      for (final e in s.exercises) {
        for (var i = 0; i < e.sets.length; i++) {
          final st = e.sets[i];
          rows.writeln(
            [
              day,
              _csv(e.name),
              e.primary,
              i + 1,
              st.reps,
              _num(st.weight),
              _num(st.volume),
              _num(st.oneRm),
              st.km == null ? '' : _num(st.km!),
              st.sec ?? '',
              st.rpe == null ? '' : _num(st.rpe!),
            ].join(','),
          );
        }
      }
    }
    return rows.toString();
  }

  static String _csv(String v) => v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

  static String _num(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Map<String, dynamic>? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
