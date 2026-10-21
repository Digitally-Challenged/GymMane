import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/apple_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gymmane/capabilities');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('missing Apple host never attempts optional extensions', () async {
    final result = await AppleCapabilities.query();
    expect(result.homeWidgets, isFalse);
    expect(result.liveActivities, isFalse);
  });

  test('only explicit native capability grants enable extensions', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'homeWidgets': true, 'liveActivities': 'true'});
    final result = await AppleCapabilities.query();
    expect(result.homeWidgets, isTrue);
    expect(result.liveActivities, isFalse);
  });

  test('native capability failure leaves optional features disabled', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'unavailable'));
    final result = await AppleCapabilities.query();
    expect(result.homeWidgets, isFalse);
    expect(result.liveActivities, isFalse);
  });
}
