import 'sync_transport.dart';

/// Every mutating method must complete its durable transaction before returning.
/// Remote application must never create outgoing operations. Namespaces are
/// explicit on all methods so a late response cannot mutate the current user.
abstract interface class SyncRepositoryPort {
  Future<void> selectNamespace(String namespace);
  Future<List<SyncJson>> pendingOperations(String namespace);
  Future<void> applyPushResults(String namespace, List<SyncJson> results);
  Future<void> applyPullPage(String namespace, List<SyncJson> entities, String nextCursor);
  Future<int> pendingCount(String namespace);
  Future<String> cursor(String namespace);
  Future<Map<String, int>> guestPreview();
  Future<void> adoptGuest(String namespace);
  Future<List<SyncJson>> conflicts(String namespace);
  Future<void> resolveConflict(String namespace, SyncJson conflict, {required bool keepLocal});
}
