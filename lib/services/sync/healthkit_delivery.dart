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
  Future<void> _requirePhone() async {
    if (!await isPhone()) {
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

  void invalidate() {
    enabled = false;
    records = {};
    workouts = [];
    notifyListeners();
  }

  Future<void> refresh() async {
    await _run(() async {
      final ledger = await store.read();
      enabled = ledger['enabled'] == true;
      records = jsonObject(ledger['records'] ?? <String, dynamic>{});
      workouts = await store.eligibleWorkouts();
    });
  }

  Future<void> designate(bool value) async {
    await _run(() async {
      final namespace = store.namespace;
      if (value) await _requirePhone();
      if (value && await adapter.authorization() != HealthKitAuthorization.authorized) {
        throw SyncFailure(t.syncAllowAppleHealthWorkoutAccessFirst);
      }
      if (namespace != store.namespace) throw SyncFailure(t.syncAccountChangedRefreshExports);
      final ledger = await store.read();
      ledger['enabled'] = value;
      await store.write(namespace, ledger);
      enabled = value;
    });
  }

  Future<void> export(SyncJson workout) async {
    await _run(() async {
      final namespace = store.namespace;
      await _requirePhone();
      if (namespace != store.namespace) throw SyncFailure(t.syncAccountChangedRefreshExports);
      final ledger = await store.read();
      if (ledger['enabled'] != true) {
        throw SyncFailure(t.syncDesignateThisIPhoneForAppleHealthExports);
      }
      final eligible = await store.eligibleWorkouts();
      final id = workout['id'];
      if (!eligible.any((entry) => entry['id'] == id && jsonEncode(entry) == jsonEncode(workout))) {
        throw SyncFailure(t.syncWorkoutChangedOrIsNotEligibleRefresh);
      }
      if (namespace != store.namespace) throw SyncFailure(t.syncAccountChangedRefreshExports);
      final entries = jsonObject(ledger['records'] ??= <String, dynamic>{});
      final old = entries[id] == null ? null : jsonObject(entries[id]);
      if (old != null && ['sending', 'unknown'].contains(old['status'])) {
        throw SyncFailure(t.syncReconcileThePreviousAttemptBeforeExportingA);
      }
      final fingerprint = jsonEncode(workout);
      if (old?['status'] == 'confirmed' && old?['fingerprint'] == fingerprint) return;
      final version = (old?['revision'] as int? ?? 0) + 1;
      final end = DateTime.parse(workout['d'] as String);
      final seconds = (workout['dur'] as num).toDouble();
      final native = HealthKitWorkout(
        id: id as String,
        revision: version,
        startTime: end.subtract(Duration(microseconds: (seconds * 1000000).round())),
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
      await _deliver(namespace, ledger, id);
    });
  }

  Future<void> reconcile(String id) async {
    await _run(() async {
      final namespace = store.namespace;
      await _requirePhone();
      if (namespace != store.namespace) throw SyncFailure(t.syncAccountChangedRefreshExports);
      final ledger = await store.read();
      if (ledger['enabled'] != true) throw SyncFailure(t.syncAppleHealthExportIsDisabled);
      final entry = jsonObject(jsonObject(ledger['records'])[id]);
      if (!['sending', 'unknown'].contains(entry['status'])) return;
      // HealthKit sync identifier + version makes this an idempotent upsert,
      // never a new randomly identified workout after response loss.
      await _deliver(namespace, ledger, id);
    });
  }

  Future<void> remove(String id) async {
    await _run(() async {
      final namespace = store.namespace;
      await _requirePhone();
      final ledger = await store.read();
      if (namespace != store.namespace) throw SyncFailure(t.syncAccountChangedRefreshExports);
      final entry = jsonObject(jsonObject(ledger['records'])[id]);
      if (entry['status'] != 'confirmed') {
        throw SyncFailure(t.syncReconcileTheCurrentExportBeforeDeleting);
      }
      entry['revision'] = (entry['revision'] as int) + 1;
      entry['operation'] = 'delete';
      entry['status'] = 'sending';
      await store.write(namespace, ledger);
      await _deliver(namespace, ledger, id);
    });
  }

  Future<void> _deliver(String namespace, SyncJson ledger, String id) async {
    final entry = jsonObject(jsonObject(ledger['records'])[id]);
    final payload = jsonObject(entry['payload']);
    try {
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
      entry['status'] = entry['operation'] == 'delete' ? 'deleted' : 'confirmed';
      await store.write(namespace, ledger);
    } catch (_) {
      entry['status'] = 'unknown';
      await store.write(namespace, ledger);
      rethrow;
    } finally {
      if (store.namespace == namespace) records = jsonObject(ledger['records']);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    final namespace = store.namespace;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await action();
    } on SyncFailure catch (error) {
      message = error.message;
    } catch (_) {
      message = t.syncAppleHealthOperationDidNotCompleteAny;
    } finally {
      if (namespace != store.namespace) {
        enabled = false;
        records = {};
        workouts = [];
      }
      busy = false;
      notifyListeners();
    }
  }
}
