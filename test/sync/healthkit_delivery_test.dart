import 'dart:convert';
import 'dart:async';
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

class DelayedLedger extends Ledger {
  final pending = Completer<List<SyncJson>>();
  final entered = Completer<void>();
  int reads = 0;
  @override
  Future<List<SyncJson>> eligibleWorkouts() async {
    reads++;
    if (reads == 1) {
      entered.complete();
      return pending.future;
    }
    return eligible;
  }
}

class OperationGate {
  OperationGate(this.boundary);
  final String boundary;
  final entered = Completer<void>();
  final released = Completer<void>();

  Future<void> pause(String at) async {
    if (boundary != at || entered.isCompleted) return;
    entered.complete();
    await released.future;
  }
}

class OperationLedger extends Ledger {
  OperationGate? gate;
  int writes = 0;
  @override
  Future<SyncJson> read() async {
    final ledger = await super.read();
    await gate?.pause('read');
    return ledger;
  }

  @override
  Future<List<SyncJson>> eligibleWorkouts() async {
    final candidates = await super.eligibleWorkouts();
    await gate?.pause('candidates');
    return candidates;
  }

  @override
  Future<void> write(String namespace, SyncJson ledger) async {
    writes++;
    await super.write(namespace, ledger);
    // The disk commit can succeed before its completion reaches the caller.
    await gate?.pause('intent');
  }
}

class OperationNative extends Native {
  OperationGate? gate;
  bool failAfterNative = false;
  @override
  Future<int> deleteWorkout({required String id, required int revision}) async {
    final count = await super.deleteWorkout(id: id, revision: revision);
    await gate?.pause('native');
    if (failAfterNative) throw StateError('native response lost');
    return count;
  }

  int permissionRequests = 0;
  @override
  Future<HealthKitAuthorization> authorization() async {
    permissionRequests++;
    await gate?.pause('authorization');
    return super.authorization();
  }

  @override
  Future<HealthKitSaveReceipt> saveWorkout(HealthKitWorkout value) async {
    final receipt = await super.saveWorkout(value);
    await gate?.pause('native');
    if (failAfterNative) throw StateError('native response lost');
    return receipt;
  }
}

void main() {
  test('confirmed export cannot resume after A guest A during phone check', () async {
    final gate = OperationGate('phone');
    final ledger = OperationLedger()
      ..namespace = 'account-a'
      ..data = {'enabled': true};
    final native = OperationNative();
    final delivery = HealthKitDelivery(
      ledger,
      adapter: native,
      isPhone: () async {
        await gate.pause('phone');
        return true;
      },
    );
    final exporting = delivery.export(workout);
    await gate.entered.future;
    ledger.namespace = 'guest';
    delivery.invalidate();
    ledger.namespace = 'account-a';
    delivery.invalidate();
    gate.released.complete();
    await exporting;
    expect(native.saves, isEmpty);
    expect(native.deletions, isEmpty);
    expect(ledger.writes, 0);
    expect(delivery.enabled, false);
    delivery.dispose();
  });
  for (final operation in ['designate', 'disable', 'export', 'remove', 'reconcileSave', 'reconcileDelete']) {
    final boundaries = switch (operation) {
      'designate' => ['phone', 'authorization', 'read', 'intent'],
      'disable' => ['read', 'intent'],
      'export' => ['phone', 'read', 'candidates', 'intent'],
      'remove' => ['phone', 'read', 'intent'],
      _ => ['phone', 'read'],
    };
    for (final boundary in boundaries) {
      for (final returnToA in [false, true]) {
        test(
          '$operation stops after $boundary when account ${returnToA ? 'returns to A' : 'switches to B'}',
          () async {
            final ledger = OperationLedger()
              ..namespace = 'account-a'
              ..data = {'enabled': true};
            final native = OperationNative();
            OperationGate? phoneGate;
            final delivery = HealthKitDelivery(
              ledger,
              adapter: native,
              isPhone: () async {
                await phoneGate?.pause('phone');
                return true;
              },
            );
            if (['remove', 'reconcileSave', 'reconcileDelete'].contains(operation)) {
              native.loseResponse = operation == 'reconcileSave';
              await delivery.export(workout);
              native.loseResponse = false;
              if (operation == 'reconcileDelete') {
                // An interrupted prior delete is a durable reconciliation request.
                final entry = ledger.data['records'][workoutId] as Map;
                entry['operation'] = 'delete';
                entry['status'] = 'unknown';
                entry['revision'] = 2;
              }
            }
            final before = jsonEncode(ledger.data);
            ledger.writes = 0;
            native.saves.clear();
            native.deletions.clear();
            native.permissionRequests = 0;
            final gate = OperationGate(boundary);
            ledger.gate = gate;
            native.gate = gate;
            phoneGate = gate;
            final pending = switch (operation) {
              'designate' => delivery.designate(true),
              'disable' => delivery.designate(false),
              'export' => delivery.export(workout),
              'remove' => delivery.remove(workoutId),
              _ => delivery.reconcile(workoutId),
            };
            await gate.entered.future;
            ledger.namespace = returnToA ? 'guest' : 'account-b';
            delivery.invalidate();
            if (returnToA) {
              ledger.namespace = 'account-a';
              delivery.invalidate();
            }
            gate.released.complete();
            await pending;
            expect(native.saves, isEmpty);
            expect(native.deletions, isEmpty);
            expect(ledger.writes, boundary == 'intent' ? 1 : 0);
            if (boundary != 'intent') expect(jsonEncode(ledger.data), before);
            if (boundary == 'intent' && ['export', 'remove'].contains(operation)) {
              expect(ledger.data['records'][workoutId]['status'], 'sending');
              expect(
                ledger.data['records'][workoutId]['operation'],
                operation == 'remove' ? 'delete' : 'save',
              );
            }
            if (boundary == 'phone') expect(native.permissionRequests, 0);
            expect(delivery.records, isEmpty);
            expect(delivery.enabled, false);
            expect(delivery.message, isNull);
            delivery.dispose();
          },
        );
      }
    }
  }

  for (final deleting in [false, true]) {
    for (final failAfterNative in [false, true]) {
      test(
        'invalidation after native ${deleting ? 'delete' : 'save'} starts preserves reconciliation with response loss $failAfterNative',
        () async {
          final ledger = OperationLedger()
            ..namespace = 'account-a'
            ..data = {'enabled': true};
          final native = OperationNative();
          final delivery = HealthKitDelivery(ledger, adapter: native, isPhone: () async => true);
          if (deleting) await delivery.export(workout);
          ledger.writes = 0;
          final gate = OperationGate('native');
          native.gate = gate;
          native.failAfterNative = failAfterNative;
          final pending = deleting ? delivery.remove(workoutId) : delivery.export(workout);
          await gate.entered.future;
          expect(native.saves, hasLength(1));
          expect(native.deletions, deleting ? ['$workoutId:2'] : isEmpty);
          ledger.namespace = 'guest';
          delivery.invalidate();
          ledger.namespace = 'account-a';
          delivery.invalidate();
          gate.released.complete();
          await pending;
          expect(ledger.writes, 1);
          expect(ledger.data['records'][workoutId]['status'], 'sending');
          expect(native.saves, hasLength(1));
          expect(native.deletions, deleting ? ['$workoutId:2'] : isEmpty);
          expect(delivery.records, isEmpty);
          native.failAfterNative = false;
          await delivery.reconcile(workoutId);
          if (deleting) {
            expect(native.deletions, ['$workoutId:2', '$workoutId:2']);
            expect(ledger.data['records'][workoutId]['status'], 'deleted');
          } else {
            expect(native.saves.map((save) => save.revision), [1, 1]);
            expect(ledger.data['records'][workoutId]['status'], 'confirmed');
          }
          delivery.dispose();
        },
      );
    }
  }
  test('refresh during a lookup is not lost and stale account data is suppressed', () async {
    final ledger = DelayedLedger();
    final delivery = HealthKitDelivery(ledger);
    final first = delivery.refresh();
    // Explicitly enter the delayed candidate boundary.
    await ledger.entered.future;
    ledger.namespace = 'account-b';
    ledger.eligible = [
      {...workout, 'n': 'Account B'},
    ];
    delivery.invalidate();
    final next = delivery.refresh();
    ledger.pending.complete([
      {...workout, 'n': 'Account A private'},
    ]);
    await first;
    await next;
    expect(delivery.workouts.single['n'], 'Account B');
    expect(delivery.busy, false);
    delivery.dispose();
  });
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
