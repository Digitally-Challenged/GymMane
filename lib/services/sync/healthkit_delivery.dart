import '../../l10n/l10n.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../apple_capabilities.dart';
import '../integrations/healthkit/healthkit_adapter.dart';
import 'sync_transport.dart';

abstract interface class HealthDeliveryStore {
  String get namespace;
  Future<SyncJson> read();
  Future<void> write(String namespace, SyncJson ledger);
  Future<List<SyncJson>> eligibleWorkouts();
}

/// Explicit exports only, on the iPhone designated by the user. A durable intent
/// precedes every native call. Retrying an unknown save reuses its immutable
/// payload and HealthKit sync version (native idempotent reconciliation).
class HealthKitDelivery extends ChangeNotifier {
  HealthKitDelivery(this.store, {this.adapter = const HealthKitAdapter(), this.isPhone = _nativePhone});
  final Future<bool> Function() isPhone;
  static Future<bool> _nativePhone() async => (await AppleCapabilities.current).isPhone;
  Future<void> _requirePhone(_HealthOperation operation) async {
    final phone = await isPhone();
    _requireCurrent(operation);
    if (!phone) {
      throw SyncFailure(t.syncExportFromYourDesignatedIPhoneThisDevice);
    }
  }

  final HealthDeliveryStore store;
  final HealthKitAdapter adapter;
  bool busy = false;
  bool enabled = false;
  String? message;
  SyncJson records = {};
  List<SyncJson> workouts = [];
  int _generation = 0;
  bool _refreshAgain = false;

  void invalidate() {
    ++_generation;
    enabled = false;
    records = {};
    workouts = [];
    message = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (busy) {
      _refreshAgain = true;
      return;
    }
    await _run((operation) async {
      final ledger = await store.read();
      _requireCurrent(operation);
      final candidates = await store.eligibleWorkouts();
      _requireCurrent(operation);
      enabled = ledger['enabled'] == true;
      records = jsonObject(ledger['records'] ?? <String, dynamic>{});
      workouts = candidates;
    });
  }

  Future<void> designate(bool value) async {
    await _run((operation) async {
      final namespace = operation.namespace;
      if (value) await _requirePhone(operation);
      _requireCurrent(operation);
      if (value) {
        final authorization = await adapter.authorization();
        _requireCurrent(operation);
        if (authorization != HealthKitAuthorization.authorized) {
          throw SyncFailure(t.syncAllowAppleHealthWorkoutAccessFirst);
        }
      }
      _requireCurrent(operation);
      final ledger = await store.read();
      _requireCurrent(operation);
      ledger['enabled'] = value;
      await store.write(namespace, ledger);
      _requireCurrent(operation);
      enabled = value;
    });
  }

  Future<void> export(SyncJson workout) async {
    await _run((operation) async {
      final namespace = operation.namespace;
      await _requirePhone(operation);
      _requireCurrent(operation);
      final ledger = await store.read();
      _requireCurrent(operation);
      if (ledger['enabled'] != true) {
        throw SyncFailure(t.syncDesignateThisIPhoneForAppleHealthExports);
      }
      final eligible = await store.eligibleWorkouts();
      _requireCurrent(operation);
      final id = workout['id'];
      if (!eligible.any((entry) => entry['id'] == id && jsonEncode(entry) == jsonEncode(workout))) {
        throw SyncFailure(t.syncWorkoutChangedOrIsNotEligibleRefresh);
      }
      _requireCurrent(operation);
      final entries = jsonObject(ledger['records'] ??= <String, dynamic>{});
      final old = entries[id] == null ? null : jsonObject(entries[id]);
      if (old != null && ['sending', 'unknown'].contains(old['status'])) {
        throw SyncFailure(t.syncReconcileThePreviousAttemptBeforeExportingA);
      }
      final fingerprint = jsonEncode(workout);
      if (old?['status'] == 'confirmed' && old?['fingerprint'] == fingerprint) return;
      final version = (old?['revision'] as int? ?? 0) + 1;
      final recordedStart = workout['startedAt'];
      final start = recordedStart is String ? DateTime.tryParse(recordedStart) : null;
      if (start == null || !start.isUtc) {
        throw SyncFailure(t.syncHealthStartTimeRequired);
      }
      final end = DateTime.parse(workout['d'] as String);
      final seconds = (workout['dur'] as num).toDouble();
      final native = HealthKitWorkout(
        id: id as String,
        revision: version,
        startTime: start,
        endTime: end,
        durationSeconds: seconds,
        name: workout['n'] as String? ?? 'GymMane workout',
      );
      entries[id] = {
        'revision': version,
        'status': 'sending',
        'operation': 'save',
        'fingerprint': fingerprint,
        'payload': native.toMap(),
      };
      await store.write(namespace, ledger);
      _requireCurrent(operation);
      await _deliver(operation, ledger, id);
    });
  }

  Future<void> reconcile(String id) async {
    await _run((operation) async {
      await _requirePhone(operation);
      _requireCurrent(operation);
      final ledger = await store.read();
      _requireCurrent(operation);
      if (ledger['enabled'] != true) throw SyncFailure(t.syncAppleHealthExportIsDisabled);
      final entry = jsonObject(jsonObject(ledger['records'])[id]);
      if (!['sending', 'unknown'].contains(entry['status'])) return;
      // HealthKit sync identifier + version makes this an idempotent upsert,
      // never a new randomly identified workout after response loss.
      _requireCurrent(operation);
      await _deliver(operation, ledger, id);
    });
  }

  Future<void> remove(String id) async {
    await _run((operation) async {
      final namespace = operation.namespace;
      await _requirePhone(operation);
      _requireCurrent(operation);
      final ledger = await store.read();
      _requireCurrent(operation);
      final entry = jsonObject(jsonObject(ledger['records'])[id]);
      if (entry['status'] != 'confirmed') {
        throw SyncFailure(t.syncReconcileTheCurrentExportBeforeDeleting);
      }
      entry['revision'] = (entry['revision'] as int) + 1;
      entry['operation'] = 'delete';
      entry['status'] = 'sending';
      await store.write(namespace, ledger);
      _requireCurrent(operation);
      await _deliver(operation, ledger, id);
    });
  }

  Future<void> _deliver(_HealthOperation operation, SyncJson ledger, String id) async {
    final namespace = operation.namespace;
    final entry = jsonObject(jsonObject(ledger['records'])[id]);
    final payload = jsonObject(entry['payload']);
    try {
      _requireCurrent(operation);
      if (entry['operation'] == 'delete') {
        await adapter.deleteWorkout(id: id, revision: entry['revision'] as int);
      } else {
        await adapter.saveWorkout(
          HealthKitWorkout(
            id: id,
            revision: payload['revision'] as int,
            startTime: DateTime.parse(payload['startTime'] as String),
            endTime: DateTime.parse(payload['endTime'] as String),
            durationSeconds: (payload['durationSeconds'] as num).toDouble(),
            name: payload['name'] as String,
          ),
        );
      }
      // A native call already started may finish after account invalidation.
      // Keep its durable intent unresolved for explicit reconciliation.
      if (!_isCurrent(operation)) return;
      entry['status'] = entry['operation'] == 'delete' ? 'deleted' : 'confirmed';
      await store.write(namespace, ledger);
    } catch (_) {
      if (!_isCurrent(operation)) return;
      entry['status'] = 'unknown';
      await store.write(namespace, ledger);
      rethrow;
    } finally {
      if (_isCurrent(operation)) records = jsonObject(ledger['records']);
    }
  }

  bool _isCurrent(_HealthOperation operation) =>
      operation.namespace == store.namespace && operation.generation == _generation;

  void _requireCurrent(_HealthOperation operation) {
    if (!_isCurrent(operation)) throw SyncFailure(t.syncAccountChangedRefreshExports);
  }

  Future<void> _run(Future<void> Function(_HealthOperation) action) async {
    if (busy) return;
    final operation = _HealthOperation(store.namespace, _generation);
    busy = true;
    message = null;
    notifyListeners();
    try {
      _requireCurrent(operation);
      await action(operation);
    } on SyncFailure catch (error) {
      if (_isCurrent(operation)) message = error.message;
    } catch (_) {
      if (_isCurrent(operation)) {
        message = t.syncAppleHealthOperationDidNotCompleteAny;
      }
    } finally {
      if (!_isCurrent(operation)) {
        enabled = false;
        records = {};
        workouts = [];
      }
      busy = false;
      notifyListeners();
      if (_refreshAgain) {
        _refreshAgain = false;
        await refresh();
      }
    }
  }
}

class _HealthOperation {
  const _HealthOperation(this.namespace, this.generation);
  final String namespace;
  final int generation;
}
