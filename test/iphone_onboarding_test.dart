import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymmane/screens/onboarding_screen.dart';
import 'package:gymmane/screens/settings_screen.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/ui_kit.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.onboarded = false;
    fit.session = null;
    fit.route = 'home';
  });

  Future<void> show(WidgetTester tester, Widget child, {double scale = 2}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (_, child) => MediaQuery(
          data: MediaQueryData(size: const Size(320, 568), textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('welcome offers an immediate offline start at 200 percent text', (tester) async {
    await tester.runAsync(() async {
      await show(tester, const OnboardingScreen());
      final start = find.widgetWithText(PrimaryButton, titleCase(t.welcomeStart));
      expect(start, findsOneWidget);
      expect(tester.getSize(start).height, greaterThanOrEqualTo(44));
      await tester.tap(start);
      await tester.pump();
      expect(fit.onboarded, isTrue);
      expect(fit.route, 'train');
      expect(tester.takeException(), isNull);
      expect(fit.toJson()['onboarded'], isTrue);
      await fit.persistNow();
      expect(Store.instance.load()['onboarded'], isTrue);
    });
  });

  testWidgets('optional setup remains accessible and saves the entered name', (tester) async {
    await tester.runAsync(() async {
      await show(tester, const OnboardingScreen());
      await tester.tap(find.text(titleCase(t.next)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Offline athlete');
      await tester.tap(find.text(t.skip2));
      await tester.pump();
      expect(fit.onboarded, isTrue);
      expect(fit.toJson()['profile'], containsPair('name', 'Offline athlete'));
      expect(tester.takeException(), isNull);
      await fit.persistNow();
      expect(Store.instance.load()['profile'], containsPair('name', 'Offline athlete'));
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform only advertises supported home widgets', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('gymmane/capabilities'),
        (_) async => {'homeWidgets': false, 'liveActivities': false, 'deviceClass': 'phone'},
      );
      await show(tester, const SettingsScreen(), scale: 1);
      expect(find.text(t.addActivityWidget), platform == TargetPlatform.iOS ? findsNothing : findsOneWidget);
      expect(find.text(t.addTodayWidget), platform == TargetPlatform.iOS ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
