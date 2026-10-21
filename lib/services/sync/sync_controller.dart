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
  });
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
  String? get account => auth.session?.account;

  Future<void> initialize() async {
    if (config.unavailableReason != null) {
      try {
        await repository.selectNamespace('guest');
      } catch (_) {
        message = t.syncLocalAccountCouldNotBeSwitchedSafely;
        phase = SyncPhase.error;
        _notify();
        return;
      }
      phase = SyncPhase.unavailable;
      message = config.unavailableReason;
      _notify();
      return;
    }
    await _action(() async {
      await auth.restore();
      await repository.selectNamespace(account ?? 'guest');
      phase = account == null ? SyncPhase.signedOut : SyncPhase.ready;
      await _counts();
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (account != null && !busy && phase != SyncPhase.needsAuthorization) unawaited(sync());
    });
    if (account != null && phase == SyncPhase.ready) unawaited(sync());
  }

  Future<void> signIn(String email, String password) async {
    if (busy || phase == SyncPhase.unavailable) return;
    await _action(() async {
      ++_generation;
      await auth.signIn(email, password);
      try {
        await repository.selectNamespace(account!);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
      phase = SyncPhase.ready;
      await _counts();
    });
    if (phase == SyncPhase.ready) await sync();
  }

  Future<void> signOut() async {
    if (busy) return;
    await _action(() async {
      ++_generation;
      await repository.selectNamespace('guest');
      await auth.signOut();
      pendingCount = 0;
      conflicts = [];
      lastSynced = null;
      phase = SyncPhase.signedOut;
    });
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
    if (busy || account == null || phase == SyncPhase.unavailable) return;
    final namespace = account!;
    final generation = _generation;
    bool current() => !_disposed && generation == _generation && account == namespace;
    await _action(() async {
      phase = SyncPhase.syncing;
      _notify();
      // Bound each cycle; remaining durable operations are picked up next time.
      final pending = await repository.pendingOperations(namespace);
      pendingCount = await repository.pendingCount(namespace);
      _notify();
      for (var offset = 0; offset < pending.length; offset += 100) {
        final token = await auth.accessToken();
        if (!current()) return;
        final result = await transport.push(token, pending.skip(offset).take(100).toList());
        if (!current()) return;
        await repository.applyPushResults(namespace, result);
      }
      var cursor = await repository.cursor(namespace);
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
        cursor = result['nextCursor'] as String;
        if (result['hasMore'] == false) {
          lastSynced = DateTime.now();
          break;
        }
      }
      await _counts();
      phase = SyncPhase.ready;
    });
  }

  void localChanged() {
    _localTimer?.cancel();
    _localTimer = Timer(const Duration(milliseconds: 500), () async {
      if (busy || account == null || _disposed) return;
      try {
        await _counts();
        _notify();
      } catch (_) {
        /* Durable sync reports errors on its next pass. */
      }
    });
  }

  Future<void> _counts() async {
    final namespace = account;
    if (namespace == null) return;
    final pending = await repository.pendingCount(namespace);
    final retained = await repository.conflicts(namespace);
    if (account != namespace) return;
    pendingCount = pending;
    conflicts = retained;
  }

  Future<void> _action(Future<void> Function() action) async {
    _busy = true;
    message = null;
    _notify();
    try {
      await action();
    } on SyncFailure catch (error) {
      phase = error.needsAuthorization
          ? SyncPhase.needsAuthorization
          : error.retryable
          ? SyncPhase.offline
          : SyncPhase.error;
      message = error.message;
    } catch (_) {
      phase = SyncPhase.error;
      message = t.syncSyncCouldNotCompleteSafelyLocalChanges;
    } finally {
      _busy = false;
      _notify();
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
    _localTimer?.cancel();
    super.dispose();
  }
}
