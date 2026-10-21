import '../local_store.dart';
import 'healthkit_delivery.dart';
import 'sync_transport.dart';

class StoreHealthDelivery implements HealthDeliveryStore {
  StoreHealthDelivery(this.store);
  final Store store;
  @override
  String get namespace => store.repository.namespace;
  @override
  Future<SyncJson> read() async => store.repository.deliveryLedger(namespace, 'healthkit');
  @override
  Future<void> write(String namespace, SyncJson ledger) =>
      store.repository.saveDeliveryLedger(namespace, 'healthkit', ledger);
  @override
  Future<List<SyncJson>> eligibleWorkouts() async => [
    for (final entity in await exportableWorkouts(store)) jsonObject(entity['payload']),
  ];
}

Future<List<SyncJson>> exportableWorkouts(Store store, {bool syncedOnly = false}) async {
  await store.repository.flushed;
  final entities = store.repository.exportableWorkouts(store.repository.namespace);
  return syncedOnly
      ? entities
            .where((entity) => (entity['revision'] as int? ?? 0) > 0 && entity['pending'] == false)
            .toList()
      : entities;
}
