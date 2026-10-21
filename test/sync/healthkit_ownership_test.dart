import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/models/workout.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/services/sync/store_sync_repository.dart';
import 'package:gymmane/services/sync/store_health_delivery.dart';
import 'package:gymmane/services/sync/healthkit_delivery.dart';
import 'package:gymmane/state/fit_state.dart';
import 'healthkit_delivery_test.dart' show Native;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'guest adoption transfers one Health identity with monotonic versions and fences other accounts',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Store.instance.init();
      fit.resetAllData();
      final workout = LoggedSession(
        DateTime.utc(2026, 10, 20),
        60,
        [],
        name: 'Guest',
        startedAt: DateTime.utc(2026, 10, 19, 23, 58),
      );
      fit.sessions.add(workout);
      await fit.persistNow(rethrowErrors: true);
      final native = Native();
      final delivery = HealthKitDelivery(
        StoreHealthDelivery(Store.instance),
        adapter: native,
        isPhone: () async => true,
      );
      final repository = StoreSyncRepository(Store.instance);
      await delivery.designate(true);
      await delivery.export(workout.toJson());
      expect(native.saves.single.revision, 1);
      final staleGuest = Store.instance.repository.deliveryLedger('guest', 'healthkit');
      await repository.selectNamespace('account-a');
      await repository.adoptGuest('account-a');
      fit.sessions.single.name = 'Updated';
      await fit.persistNow(rethrowErrors: true);
      await delivery.designate(true);
      await delivery.export(fit.sessions.single.toJson());
      expect(delivery.message, isNull);
      expect(native.saves.map((s) => s.revision), [1, 2]);
      expect(native.saves.map((s) => s.id).toSet(), {workout.id});
      await expectLater(
        Store.instance.repository.saveDeliveryLedger('guest', 'healthkit', staleGuest),
        throwsStateError,
      );
      await repository.selectNamespace('guest');
      await delivery.remove(workout.id);
      expect(native.deletions, isEmpty);
      await repository.selectNamespace('account-b');
      await repository.adoptGuest('account-b');
      await delivery.designate(true);
      await delivery.export(fit.sessions.single.toJson());
      expect(native.saves.length, 2);
      await delivery.remove(workout.id);
      expect(native.deletions, isEmpty);
      await Store.instance.init();
      fit.loadFromStore();
      await repository.selectNamespace('account-a');
      await delivery.refresh();
      expect(delivery.records[workout.id]['revision'], 2);
      await delivery.remove(workout.id);
      expect(native.deletions, ['${workout.id}:3']);
      expect(delivery.records[workout.id]['status'], 'deleted');
      fit.saveAndExit();
      await fit.persistNow();
      delivery.dispose();
    },
  );
}
