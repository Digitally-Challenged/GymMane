import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StorageBackend {
  Future<Map<String, dynamic>?> read();

  /// Must commit the complete snapshot atomically or leave it unchanged.
  Future<void> write(Map<String, dynamic> snapshot);
}

class PreferencesBackend implements StorageBackend {
  PreferencesBackend(this.preferences);
  final SharedPreferences preferences;
  static const key = 'gymmane_repository_v1';
  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = preferences.getString(key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    if (!await preferences.setString(key, jsonEncode(snapshot))) {
      throw StateError('Local storage rejected the commit');
    }
  }
}
