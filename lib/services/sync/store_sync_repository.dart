import '../../l10n/l10n.dart';
import '../../state/fit_state.dart';
import '../local_store.dart';
import 'sync_repository_port.dart';
import 'sync_transport.dart';

/// Production adapter for the transactional local repository.
class StoreSyncRepository implements SyncRepositoryPort {
  StoreSyncRepository(this.store);
  final Store store;
  @override
  Future<void> selectNamespace(String namespace) async {
    if (store.repository.namespace == namespace) return;
    await fit.persistNow(rethrowErrors: true);
    await store.repository.selectNamespace(namespace);
    fit.loadFromStore();
  }

  @override
  Future<List<SyncJson>> pendingOperations(String namespace) => store.repository.pendingOperations(namespace);
  @override
  Future<void> applyPushResults(String namespace, List<SyncJson> results) async {
    await fit.applySyncChange(() => store.repository.applyPushResults(namespace, results));
  }

  @override
  Future<void> applyPullPage(String namespace, List<SyncJson> entities, String nextCursor) async {
    await fit.applySyncChange(() => store.repository.applyPullPage(namespace, entities, nextCursor));
  }

  @override
  Future<int> pendingCount(String namespace) async => store.repository.pendingCount(namespace);
  @override
  Future<String> cursor(String namespace) async => store.repository.cursor(namespace);
  @override
  Future<Map<String, int>> guestPreview() async => store.repository.guestCounts();
  @override
  Future<void> adoptGuest(String namespace) async {
    await fit.applySyncChange(() => store.repository.adoptGuest(namespace));
  }

  @override
  Future<List<SyncJson>> conflicts(String namespace) async =>
      store.repository.conflicts(namespace).values.map((value) {
        final remote = jsonObject(value);
        return {
          ...remote,
          'local': store.repository.entityMetadata(
            namespace,
            remote['entityType'] as String,
            remote['entityId'] as String,
          ),
        };
      }).toList();
  @override
  Future<void> resolveConflict(String namespace, SyncJson conflict, {required bool keepLocal}) async {
    await fit.applySyncChange(() async {
      final type = conflict['entityType'] as String;
      final id = conflict['entityId'] as String;
      final current = store.repository.conflicts(namespace)['$type:$id'];
      final local = store.repository.entityMetadata(namespace, type, id);
      if (current is! Map ||
          current['revision'] != conflict['revision'] ||
          local?['localRevision'] != (conflict['local'] as Map?)?['localRevision']) {
        throw SyncFailure(t.syncThisConflictChangedRefreshAndReviewBoth, status: 409);
      }
      await store.repository.resolveConflict(namespace, type, id, keepLocal: keepLocal);
    });
  }
}
