import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/local_store.dart';
import '../../services/sync/sync_controller.dart';
import '../../state/fit_state.dart';

/// Observe durable candidates without writing a snapshot during every refresh.
class DeliveryUpdates {
  DeliveryUpdates(this.onChanged, {this.sync}) {
    _account = sync?.account;
    _lastSynced = sync?.lastSynced;
    _candidates = _snapshot();
    fit.addListener(_localChanged);
    sync?.addListener(_syncChanged);
    _saves = Store.instance.acknowledgedSaves.listen((_) => _localChanged());
  }
  final VoidCallback onChanged;
  final SyncController? sync;
  String? _account;
  DateTime? _lastSynced;
  Timer? _timer;
  StreamSubscription<String>? _saves;
  bool _disposed = false;
  String? _candidates;

  String? _snapshot() {
    try {
      final repository = Store.instance.repository;
      return jsonEncode([repository.namespace, repository.exportableWorkouts(repository.namespace)]);
    } catch (_) {
      return null;
    }
  }

  void _syncChanged() {
    if (_account == sync?.account && _lastSynced == sync?.lastSynced) return;
    _account = sync?.account;
    _lastSynced = sync?.lastSynced;
    onChanged();
  }

  void _localChanged() {
    _timer?.cancel();
    // Domain edits use a 400ms save debounce. Wait for that save and its disk
    // transaction, including for guests who have no outgoing sync operations.
    _timer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await Store.instance.repository.flushed;
      } catch (_) {
        // Previews have no initialized store; their actions stay unavailable.
      }
      if (_disposed) return;
      final candidates = _snapshot();
      // FitState also emits timer/navigation updates. They must not turn into
      // repeated provider-status requests when durable workouts are unchanged.
      if (candidates == _candidates) return;
      _candidates = candidates;
      onChanged();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_saves?.cancel());
    fit.removeListener(_localChanged);
    sync?.removeListener(_syncChanged);
  }
}
