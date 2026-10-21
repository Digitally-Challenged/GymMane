import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/integrations/healthkit/healthkit_adapter.dart';
import 'package:gymmane/services/sync/healthkit_delivery.dart';
import 'package:gymmane/services/sync/sync_transport.dart';

const workoutId = '12345678-1234-1234-1234-123456789abc';
final workout = <String, dynamic>{
  'id': workoutId,
  'd': '2026-10-20T14:00:00Z',
  'startedAt': '2026-10-20T12:30:00Z',
  'dur': 3600,
  'n': 'Strength',
  'origin': 'gymmane',
};

class Ledger implements HealthDeliveryStore {
  @override
  String namespace = 'guest';
  SyncJson data = {};
  bool failWrite = false;
  List<SyncJson> eligible = [workout];
  @override
  Future<SyncJson> read() async => jsonObject(jsonDecode(jsonEncode(data)));
  @override
  Future<void> write(String namespace, SyncJson ledger) async {
    if (failWrite) throw StateError('disk unavailable');
    data = jsonObject(jsonDecode(jsonEncode(ledger)));
  }

  @override
  Future<List<SyncJson>> eligibleWorkouts() async => eligible;
}

class Native extends HealthKitAdapter {
  final saves = <HealthKitWorkout>[];
  final deletions = <String>[];
  bool loseResponse = false;
  @override
  Future<HealthKitAuthorization> authorization() async => HealthKitAuthorization.authorized;
  @override
  Future<HealthKitSaveReceipt> saveWorkout(HealthKitWorkout value) async {
    saves.add(value);
    if (loseResponse) throw StateError('response lost');
    return HealthKitSaveReceipt(
      syncIdentifier: 'com.gymmane.app.workout.${value.id}',
      revision: value.revision,
    );
  }

  @override
  Future<int> deleteWorkout({required String id, required int revision}) async {
    deletions.add('$id:$revision');
    return 1;
  }
}

void main() {
  test('exports actual start and active duration without subtracting paused time', () async {
    final native = Native();
    final delivery = HealthKitDelivery(Ledger(), adapter: native, isPhone: () async => true);
    await delivery.designate(true);
    await delivery.export(workout);
    expect(native.saves.single.startTime, DateTime.utc(2026, 10, 20, 12, 30));
    expect(native.saves.single.durationSeconds, 3600);
    expect(native.saves.single.endTime, DateTime.utc(2026, 10, 20, 14));
  });
  test('legacy missing start is unsupported without a native call or delivery intent', () async {
    final legacy = {...workout}..remove('startedAt');
    final ledger = Ledger()..eligible = [legacy];
    final native = Native();
    final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
    await delivery.designate(true);
    await delivery.export(legacy);
    expect(native.saves, isEmpty);
    expect(delivery.message, contains('start time'));
    expect(ledger.data['records'], anyOf(isNull, isEmpty));
  });

  test('explicit phone opt-in required and intent commit precedes native save', () async {
    final ledger = Ledger();
    final native = Native();
    final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
    await delivery.export(workout);
    expect(native.saves, isEmpty);
    await delivery.designate(true);
    ledger.failWrite = true;
    await delivery.export(workout);
    expect(native.saves, isEmpty);
    expect(delivery.message, isNotNull);
  });
  test('iPad cannot become a writer', () async {
    final delivery = HealthKitDelivery(Ledger(), adapter: Native(), isPhone: () async => false);
    await delivery.designate(true);
    expect(delivery.enabled, false);
    expect(delivery.message, contains('iPhone'));
  });
  test('unknown outcomes reuse immutable identifier/version and delete is explicit', () async {
    final ledger = Ledger();
    final native = Native()..loseResponse = true;
    final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
    await delivery.designate(true);
    await delivery.export(workout);
    expect(delivery.records[workoutId]['status'], 'unknown');
    await delivery.export(workout);
    expect(native.saves.length, 1);
    native.loseResponse = false;
    await delivery.reconcile(workoutId);
    expect(native.saves.map((value) => value.revision), [1, 1]);
    expect(native.saves.map((value) => value.id).toSet(), {workoutId});
    expect(delivery.records[workoutId]['status'], 'confirmed');
    await delivery.export(workout);
    expect(native.saves.length, 2);
    await delivery.remove(workoutId);
    expect(native.deletions, ['$workoutId:2']);
    expect(delivery.records[workoutId]['status'], 'deleted');
  });
}
