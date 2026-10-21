import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS workout export retains HealthKit and the signed keychain group only', () {
    final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    final keys = RegExp(
      r'<key>([^<]+)</key>',
    ).allMatches(entitlements).map((match) => match.group(1)).toSet();

    expect(keys, {'com.apple.developer.healthkit', 'keychain-access-groups'});
    expect(entitlements, matches(RegExp(r'<key>com\.apple\.developer\.healthkit</key>\s*<true\s*/>')));
    expect(entitlements, contains(r'<string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>'));
    expect(entitlements, isNot(contains('health-records')));
    expect(entitlements, isNot(contains('background-delivery')));
  });
}
