import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum HealthKitAuthorization { unsupported, notDetermined, denied, authorized }

/// A completed workout only. The caller owns opt-in, origin checks and its ledger.
final class HealthKitWorkout {
  HealthKitWorkout({
    required String id,
    required this.revision,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.name,
  }) : id = id.toLowerCase() {
    _validateIdentity(this.id, revision);
    if (!endTime.isAfter(startTime) ||
        !durationSeconds.isFinite ||
        durationSeconds <= 0 ||
        durationSeconds > endTime.difference(startTime).inMicroseconds / 1000000 + 0.001 ||
        name.trim().isEmpty ||
        name.length > 256) {
      throw ArgumentError('Invalid workout times, duration or name.');
    }
  }

  final String id;
  final int revision;
  final DateTime startTime;
  final DateTime endTime;
  final double durationSeconds;
  final String name;

  Map<String, Object> toMap() => {
    'id': id,
    'revision': revision,
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime.toUtc().toIso8601String(),
    'durationSeconds': durationSeconds,
    'name': name,
  };
}

/// An accepted sync version, not a HealthKit object UUID. HealthKit may ignore
/// the save when this version (or a newer version) already exists.
final class HealthKitSaveReceipt {
  const HealthKitSaveReceipt({required this.syncIdentifier, required this.revision});
  final String syncIdentifier;
  final int revision;
}

/// Export-only channel contract v1, `gymmane/healthkit`:
/// * availability -> {available: bool}
/// * authorization / requestAuthorization -> {status: unsupported |
///   notDetermined | denied | authorized}; these describe WRITE permission only.
/// * saveWorkout(HealthKitWorkout.toMap()) -> {syncIdentifier: String, revision: int}
/// * deleteWorkout({id: UUID, revision: positive int}) -> {deletedCount: int}
///
/// Only requestAuthorization may prompt; call it after explicit user action.
/// Mutations throw PlatformException with unsupported, permission_denied,
/// invalid_argument, save_failed, delete_failed or authorization_failed codes.
/// malformed_response means the host violated this contract. No health data is
/// read, no calories estimated, and no operation runs on web or other platforms.
class HealthKitAdapter {
  const HealthKitAdapter({MethodChannel channel = const MethodChannel('gymmane/healthkit')})
    : _channel = channel;

  final MethodChannel _channel;
  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> availability() async {
    if (!_supported) return false;
    try {
      final response = await _invoke('availability');
      if (response['available'] case final bool available) return available;
      throw _malformed();
    } on MissingPluginException {
      return false;
    }
  }

  Future<HealthKitAuthorization> authorization() async {
    if (!_supported) return HealthKitAuthorization.unsupported;
    try {
      return _authorization(await _invoke('authorization'));
    } on MissingPluginException {
      return HealthKitAuthorization.unsupported;
    }
  }

  Future<HealthKitAuthorization> requestAuthorization() async {
    _requireSupported();
    return _authorization(await _invokeMutation('requestAuthorization'));
  }

  Future<HealthKitSaveReceipt> saveWorkout(HealthKitWorkout workout) async {
    _requireSupported();
    final response = await _invokeMutation('saveWorkout', workout.toMap());
    final expected = 'com.gymmane.app.workout.${workout.id}';
    if (response['syncIdentifier'] != expected || response['revision'] != workout.revision) {
      throw _malformed();
    }
    return HealthKitSaveReceipt(syncIdentifier: expected, revision: workout.revision);
  }

  /// Deletes only this app's matching workout, up to [revision]. Zero is a valid
  /// idempotent result; newer versions and other sources are never deleted.
  Future<int> deleteWorkout({required String id, required int revision}) async {
    _validateIdentity(id, revision);
    _requireSupported();
    final response = await _invokeMutation('deleteWorkout', {'id': id.toLowerCase(), 'revision': revision});
    if (response['deletedCount'] case final int count when count >= 0) return count;
    throw _malformed();
  }

  Future<Map<Object?, Object?>> _invoke(String method, [Object? arguments]) async {
    final response = await _channel.invokeMethod<Object?>(method, arguments);
    if (response is! Map) throw _malformed();
    return response.cast<Object?, Object?>();
  }

  Future<Map<Object?, Object?>> _invokeMutation(String method, [Object? arguments]) async {
    try {
      return await _invoke(method, arguments);
    } on MissingPluginException {
      throw PlatformException(code: 'unsupported', message: 'HealthKit host is unavailable.');
    }
  }

  HealthKitAuthorization _authorization(Map<Object?, Object?> response) {
    for (final status in HealthKitAuthorization.values) {
      if (status.name == response['status']) return status;
    }
    throw _malformed();
  }

  void _requireSupported() {
    if (!_supported) {
      throw PlatformException(code: 'unsupported', message: 'HealthKit requires iOS or iPadOS.');
    }
  }

  PlatformException _malformed() =>
      PlatformException(code: 'malformed_response', message: 'Invalid response from the HealthKit host.');
}

void _validateIdentity(String id, int revision) {
  if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(id) ||
      revision < 1 ||
      revision > 9007199254740991) {
    throw ArgumentError('A UUID and positive safe-integer revision are required.');
  }
}
