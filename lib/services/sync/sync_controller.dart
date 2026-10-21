import '../../l10n/l10n.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'sync_auth.dart';
import 'sync_config.dart';
import 'sync_repository_port.dart';
import 'sync_transport.dart';

enum SyncPhase { unavailable, signedOut, ready, syncing, offline, error, needsAuthorization }

class SyncController extends ChangeNotifier {
  SyncController({
    required this.config,
    required this.auth,
    required this.repository,
    required this.transport,
    Stream<String>? acknowledgedSaves,
  }) {
    _savesSubscription = acknowledgedSaves?.listen((namespace) {
      if (namespace == account) localChanged();
    });
  }
  final SyncConfig config;
  final SyncAuth auth;
  final SyncRepositoryPort repository;
  final SyncTransport transport;
  SyncPhase phase = SyncPhase.signedOut;
  String? message;
  int pendingCount = 0;
  List<SyncJson> conflicts = [];
  DateTime? lastSynced;
  bool get busy => _busy;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  Timer? _localTimer;
  Timer? _requestTimer;
  bool _syncRequested = false;
  StreamSubscription<String>? _savesSubscription;
  Future<void>? _activeAction;
  bool _changingAccount = false;
  String? get account => auth.session?.account;

  bool get _canSync =>
      !_disposed &&
      !_changingAccount &&
      account != null &&
      config.unavailableReason == null &&
      phase != SyncPhase.unavailable &&
      phase != SyncPhase.needsAuthorization;

  /// Coalesces foreground and durable-work triggers, including during a cycle.
  void requestSync() {
    if (!_canSync) return;
    _syncRequested = true;
    _scheduleRequest();
  }

  void _scheduleRequest() {
    if (!_syncRequested || !_canSync || busy || _requestTimer != null) return;
    final namespace = account;
    final generation = _generation;
    _requestTimer = Timer(const Duration(milliseconds: 200), () {
      _requestTimer = null;
      if (_disposed || generation != _generation || account != namespace) {
        _syncRequested = false;
        return;
      }
      unawaited(sync());
    });
  }

  Future<void> initialize() async {
    if (config.unavailableReason != null) {
      await repository.selectNamespace('guest');
      phase = SyncPhase.unavailable;
      message = config.unavailableReason;
      _notify();
      return;
    }
    try {
      await auth.restore();
    } catch (_) {
      // A bad/locked vault must not expose the previously active account.
      try {
        await auth.signOut();
      } catch (_) {
        /* Guest isolation still proceeds. */
      }
      await repository.selectNamespace('guest');
      phase = SyncPhase.needsAuthorization;
      message = t.syncSignInToSync;
      _notify();
      return;
    }
    // Failure to establish a safe namespace is fatal to startup, not a sync
    // warning. main routes it to retry-only recovery before rendering app data.
    await repository.selectNamespace(account ?? 'guest');
    await _action(() async {
      phase = account == null ? SyncPhase.signedOut : SyncPhase.ready;
      await _counts();
    });
    _ensureTimer();
    if (account != null && phase == SyncPhase.ready) unawaited(sync());
  }

  void _ensureTimer() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_canSync && !busy) unawaited(sync());
    });
  }

  Future<void> signIn(String email, String password) async {
    if (busy || _changingAccount || _disposed || phase == SyncPhase.unavailable) return;
    ++_generation;
    _cancelScheduled();
    await _action(() async {
      await auth.signIn(email, password);
      try {
        await repository.selectNamespace(account!);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
      phase = SyncPhase.ready;
      lastSynced = null;
      await _counts();
    });
    if (phase == SyncPhase.ready) {
      _ensureTimer();
      await sync();
    }
  }

  Future<void> signOut() async {
    if (_disposed || _changingAccount) return;
    _changingAccount = true;
    ++_generation;
    _cancelScheduled();
    try {
      // Fence the network immediately, then serialize the namespace transition
      // with any disk application already in progress for the prior account.
      await _activeAction;
      if (_disposed) return;
      await _action(() async {
        await repository.selectNamespace('guest');
        await auth.signOut();
        pendingCount = 0;
        conflicts = [];
        lastSynced = null;
        phase = SyncPhase.signedOut;
      });
    } finally {
      _changingAccount = false;
    }
  }

  void _cancelScheduled() {
    _requestTimer?.cancel();
    _requestTimer = null;
    _localTimer?.cancel();
    _localTimer = null;
    _syncRequested = false;
  }

  Future<Map<String, int>> guestPreview() => repository.guestPreview();
  Future<void> adoptGuest() async {
    if (busy || account == null) return;
    await _action(() async {
      await repository.adoptGuest(account!);
      await _counts();
      phase = SyncPhase.ready;
    });
    if (phase == SyncPhase.ready) await sync();
  }

  Future<void> resolve(SyncJson conflict, {required bool keepLocal}) async {
    if (busy || account == null) return;
    await _action(() async {
      await repository.resolveConflict(account!, conflict, keepLocal: keepLocal);
      await _counts();
      phase = SyncPhase.ready;
    });
    if (phase == SyncPhase.ready) await sync();
  }

  Future<void> sync() async {
    if (busy || !_canSync) return;
    _requestTimer?.cancel();
    _requestTimer = null;
    _syncRequested = false;
    final namespace = account!;
    final generation = _generation;
    bool current() => !_disposed && generation == _generation && account == namespace;
    await _action(() async {
      phase = SyncPhase.syncing;
      _notify();
      // Re-read after receipts: the repository exposes at most 100 operations
      // and serializes successive edits to the same entity behind its receipt.
      for (var batch = 0; batch < 10; batch++) {
        final pending = await repository.pendingOperations(namespace);
        if (!current()) return;
        pendingCount = await repository.pendingCount(namespace);
        if (!current()) return;
        _notify();
        if (pending.isEmpty) break;
        final token = await auth.accessToken();
        if (!current()) return;
        final result = await transport.push(token, pending.take(100).toList());
        if (!current()) return;
        await repository.applyPushResults(namespace, result);
        if (!current()) return;
      }
      var cursor = await repository.cursor(namespace);
      if (!current()) return;
      var hasMore = false;
      for (var page = 0; page < 100; page++) {
        final token = await auth.accessToken();
        if (!current()) return;
        final result = await transport.pull(token, cursor);
        if (!current()) return;
        await repository.applyPullPage(
          namespace,
          jsonList(result['entities']),
          result['nextCursor'] as String,
        );
        if (!current()) return;
        cursor = result['nextCursor'] as String;
        hasMore = result['hasMore'] as bool;
        if (!hasMore) {
          lastSynced = DateTime.now();
          break;
        }
      }
      await _counts();
      if (!current()) return;
      phase = SyncPhase.ready;
      // Saves made during pulls and batches beyond this bounded cycle continue
      // promptly. Conflicted operations are excluded by pendingOperations.
      final remaining = await repository.pendingOperations(namespace);
      if (current() && (hasMore || remaining.isNotEmpty)) requestSync();
    });
  }

  void localChanged() {
    if (_disposed || account == null || config.unavailableReason != null) return;
    final namespace = account!;
    final generation = _generation;
    bool current() => !_disposed && generation == _generation && account == namespace;
    _localTimer?.cancel();
    _localTimer = Timer(const Duration(milliseconds: 200), () async {
      _localTimer = null;
      if (!current()) return;
      try {
        await _counts();
        if (!current()) return;
        _notify();
        // A running cycle checks remaining work itself. Persisting an unchanged
        // snapshot during remote application must not request another pull.
        if (busy || !_canSync) return;
        final pending = await repository.pendingOperations(namespace);
        if (current() && !busy && pending.isNotEmpty) requestSync();
      } catch (_) {
        /* Durable sync reports errors on its next pass. */
      }
    });
  }

  Future<void> _counts() async {
    final namespace = account;
    final generation = _generation;
    if (namespace == null) return;
    final pending = await repository.pendingCount(namespace);
    final retained = await repository.conflicts(namespace);
    if (_disposed || generation != _generation || account != namespace) return;
    pendingCount = pending;
    conflicts = retained;
  }

  Future<void> _action(Future<void> Function() action) {
    final running = _runAction(action);
    _activeAction = running;
    return running;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    final generation = _generation;
    bool current() => !_disposed && generation == _generation;
    _busy = true;
    message = null;
    _notify();
    try {
      await action();
    } on SyncFailure catch (error) {
      if (!current()) return;
      _syncRequested = false;
      phase = error.needsAuthorization
          ? SyncPhase.needsAuthorization
          : error.retryable
          ? SyncPhase.offline
          : SyncPhase.error;
      message = error.message;
    } catch (_) {
      if (!current()) return;
      _syncRequested = false;
      phase = SyncPhase.error;
      message = t.syncSyncCouldNotCompleteSafelyLocalChanges;
    } finally {
      if (current()) {
        try {
          await _counts();
        } catch (_) {
          // Retain the last known counts if storage itself is unavailable.
        }
      }
      _busy = false;
      _notify();
      _scheduleRequest();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _cancelScheduled();
    unawaited(_savesSubscription?.cancel());
    super.dispose();
  }
}
