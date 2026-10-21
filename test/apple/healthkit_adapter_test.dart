import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/integrations/healthkit/healthkit_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gymmane/healthkit');
  const adapter = HealthKitAdapter();
  const id = '0f68869c-e8f2-4a01-bab9-1710be636176';
  final calls = <MethodCall>[];
  Object? response;
  PlatformException? failure;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  HealthKitWorkout workout({double duration = 1200, int revision = 1}) => HealthKitWorkout(
    id: id,
    revision: revision,
    startTime: DateTime.utc(2026, 10, 1, 12),
    endTime: DateTime.utc(2026, 10, 1, 12, 30),
    durationSeconds: duration,
    name: 'Strength',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    response = null;
    failure = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failure != null) throw failure!;
      return response;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('unsupported platform never calls native host or prompts', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await adapter.availability(), false);
    expect(await adapter.authorization(), HealthKitAuthorization.unsupported);
    await expectLater(
      adapter.requestAuthorization(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'unsupported')),
    );
    await expectLater(adapter.saveWorkout(workout()), throwsA(isA<PlatformException>()));
    expect(calls, isEmpty);
  });
  test('availability and authorization are passive', () async {
    response = {'available': true};
    expect(await adapter.availability(), true);
    response = {'status': 'notDetermined'};
    expect(await adapter.authorization(), HealthKitAuthorization.notDetermined);
    expect(calls.map((c) => c.method), ['availability', 'authorization']);
  });
  test('authorization completion does not imply granted access', () async {
    response = {'status': 'denied'};
    expect(await adapter.requestAuthorization(), HealthKitAuthorization.denied);
  });
  test('save preserves pauses and exports no fabricated measurements', () async {
    response = {'syncIdentifier': 'com.gymmane.app.workout.$id', 'revision': 1};
    final receipt = await adapter.saveWorkout(workout());
    expect(receipt.revision, 1);
    expect(calls.single.arguments, {
      'id': id,
      'revision': 1,
      'name': 'Strength',
      'durationSeconds': 1200.0,
      'startTime': '2026-10-01T12:00:00.000Z',
      'endTime': '2026-10-01T12:30:00.000Z',
    });
  });
  test('delete carries revision fence and accepts idempotent zero', () async {
    response = {'deletedCount': 0};
    expect(await adapter.deleteWorkout(id: id.toUpperCase(), revision: 3), 0);
    expect(calls.single.arguments, {'id': id, 'revision': 3});
  });
  test('permission failure is explicit, not a successful ledger receipt', () async {
    failure = PlatformException(code: 'permission_denied');
    await expectLater(
      adapter.saveWorkout(workout()),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'permission_denied')),
    );
  });
  test('invalid duration or identity is rejected before channel call', () async {
    for (final duration in [0.0, -1.0, double.nan, double.infinity, 1801.0]) {
      expect(() => workout(duration: duration), throwsArgumentError);
    }
    expect(() => workout(revision: 0), throwsArgumentError);
    await expectLater(adapter.deleteWorkout(id: 'all', revision: 1), throwsArgumentError);
    expect(calls, isEmpty);
  });
  test('malformed native responses cannot claim success', () async {
    response = {'status': 'granted'};
    await expectLater(adapter.authorization(), throwsA(isA<PlatformException>()));
    response = {'syncIdentifier': 'wrong', 'revision': 1};
    await expectLater(adapter.saveWorkout(workout()), throwsA(isA<PlatformException>()));
    response = {'deletedCount': -1};
    await expectLater(adapter.deleteWorkout(id: id, revision: 1), throwsA(isA<PlatformException>()));
  });
  test('missing host is unsupported for passive checks and mutations', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await adapter.availability(), false);
    expect(await adapter.authorization(), HealthKitAuthorization.unsupported);
    await expectLater(
      adapter.saveWorkout(workout()),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'unsupported')),
    );
  });
}
