import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/screens/tool_detail_screen.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_colors.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/plates/barbell_view.dart';
import 'package:gymmane/widgets/plates/plate_disc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reverseTab = "What's on it?";

void _reset() {
  fit.setUnits('kg');
  fit.places.clear();
  fit.activePlaceId = '';
  fit.plateBar = null;
  fit.plateTarget = 100;
  fit.clearReverse();
}

/// Opens Tools → Plates the way the app does: the screen is rebuilt whenever `fit` changes.
Future<void> _open(WidgetTester tester, {double width = 320, double height = 640, ThemeData? theme}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  fit.activeToolId = 'plate';
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: AnimatedBuilder(animation: fit, builder: (context, _) => ToolDetailScreen()),
      ),
    ),
  );
}

/// Switches units without leaving the save debounce timer pending when the test ends.
void _units(String units) {
  fit.setUnits(units);
  unawaited(fit.persistNow());
}

void _lbTarget(double lb) {
  _units('lb');
  fit.plateTarget = fit.fromDisplayWeight(lb);
}

Finder _disc(double size) => find.byWidgetPredicate((w) => w is PlateDisc && w.size == size);

Finder _inc(double size) =>
    find.descendant(of: _disc(size), matching: find.byKey(const ValueKey('plate-disc-inc')));

Finder _dec(double size) =>
    find.descendant(of: _disc(size), matching: find.byKey(const ValueKey('plate-disc-dec')));

/// Taps [target] after scrolling it into view, the way a thumb would.
Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

Future<void> _openReverse(WidgetTester tester) async {
  await tester.tap(find.text(_reverseTab));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    _reset();
  });

  group('plate target', () {
    test('a lb target typed in loads the same plates as the number shown', () {
      _units('lb');
      for (var lb = 55; lb <= 695; lb += 5) {
        fit.bumpPlateTarget(fit.fromDisplayWeight(lb.toDouble()) - fit.plateTarget);
        expect(fit.plateBreakdown, fit.platesPerSide(lb.toDouble(), 45), reason: '$lb lb');
      }
    });

    test('315 lb is three 45s a side', () {
      _units('lb');
      fit.bumpPlateTarget(fit.fromDisplayWeight(315) - fit.plateTarget);
      expect(fit.plateBreakdown, [(weight: 45.0, count: 3)]);
    });
  });

  group('Load tab', () {
    testWidgets('the plate tool opens on Load and shows the drawn bar', (tester) async {
      _lbTarget(275);
      await _open(tester);

      expect(find.text('Load'), findsOneWidget);
      expect(find.text(_reverseTab), findsOneWidget);
      expect(find.byType(BarbellView), findsOneWidget);
      expect(find.byType(PlateDisc), findsNothing, reason: 'the discs belong to the reverse tab');
      for (final key in ['plate-45-0', 'plate-45-1', 'plate-25-2']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(find.text('275'), findsOneWidget);
      expect(find.text('45 ×2'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('45 bar + 2 × (45 + 45 + 25) = 275'), findsOneWidget);
    });

    testWidgets('the total is also shown in the other unit', (tester) async {
      _lbTarget(275);
      await _open(tester);
      expect(find.text('124.7 kg'), findsOneWidget);

      _units('kg');
      fit.plateTarget = 100;
      await tester.pump();
      expect(find.text('220.5 lb'), findsOneWidget);
    });

    testWidgets('the - and + buttons step the target by the plate step', (tester) async {
      _lbTarget(275);
      await _open(tester);

      await tester.tap(find.byKey(const ValueKey('plate-step-inc')));
      await tester.pump();
      expect(find.text('280'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('plate-step-dec')));
      await tester.tap(find.byKey(const ValueKey('plate-step-dec')));
      await tester.pump();
      expect(find.text('270'), findsOneWidget);
    });

    testWidgets('tapping the total lets you type a target', (tester) async {
      _lbTarget(275);
      await _open(tester);

      await tester.tap(find.text('275'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), '315');
      await tester.tap(find.text('Set'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('315'), findsOneWidget);
      expect(fit.weightValue(fit.plateTarget), '315');
      expect(find.text('45 ×3'), findsOneWidget);
      expect(find.text('45 bar + 2 × (45 + 45 + 45) = 315'), findsOneWidget);
    });

    testWidgets('choosing a lighter bar puts more on each side', (tester) async {
      _lbTarget(275);
      await _open(tester);
      final option = find.ancestor(of: find.text('45 lb'), matching: find.byType(Container)).first;
      expect(
        tester.getSize(option).width,
        lessThan(150),
        reason: 'an option is as wide as its label, not the card',
      );

      await tester.tap(find.text('35 lb'));
      await tester.pump();

      expect(fit.plateBarDisplay, 35);
      expect(find.text('35 bar + 2 × (45 + 45 + 25 + 5) = 275'), findsOneWidget);
    });

    testWidgets('a target at or under the bar is just the bar', (tester) async {
      fit.plateTarget = 20;
      await _open(tester);
      expect(find.text('Just the bar.'), findsOneWidget);
      expect(find.byType(PlateDisc), findsNothing);
    });

    testWidgets('a target the stock cannot reach names the closest load in brass', (tester) async {
      fit.plateTarget = 101;
      await _open(tester);

      final warning = find.text('Closest you can load: 100 kg');
      expect(warning, findsOneWidget);
      expect(tester.widget<Text>(warning).style?.color, GymColors.light.brass);
    });
  });

  group('What\'s on it? tab', () {
    testWidgets('tapping + on a reverse disc raises the total', (tester) async {
      _units('lb');
      await _open(tester);
      await _openReverse(tester);
      expect(find.byType(PlateDisc), findsNWidgets(fit.plateSizes.length));

      await _press(tester, _inc(45));
      await tester.pump();

      expect(find.text('135'), findsOneWidget);
      expect(find.text('61.2 kg'), findsOneWidget);
      expect(fit.reverseCounts[45], 1);
    });

    testWidgets('- takes a plate off and is inert at zero', (tester) async {
      _units('lb');
      await _open(tester);
      await _openReverse(tester);

      await _press(tester, _dec(45));
      await tester.pump();
      expect(fit.reverseCounts, isEmpty);

      await _press(tester, _inc(45));
      await _press(tester, _inc(45));
      await _press(tester, _dec(45));
      await tester.pump();
      expect(fit.reverseCounts[45], 1);
      expect(find.text('135'), findsOneWidget);
    });

    testWidgets('the bar choice is shared and Clear empties the bar', (tester) async {
      _units('lb');
      await _open(tester);
      await _openReverse(tester);

      await tester.tap(find.text('35 lb'));
      await _press(tester, _inc(25));
      await tester.pump();
      expect(find.text('85'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(fit.reverseCounts, isEmpty);
      expect(fit.reverseTotal, 35);
    });

    testWidgets('the tab survives the screen rebuilding on a change', (tester) async {
      _units('lb');
      await _open(tester);
      await _openReverse(tester);
      await _press(tester, _inc(45));
      await tester.pump();

      expect(find.byType(PlateDisc), findsWidgets);
      expect(find.byType(BarbellView), findsOneWidget);
      expect(find.text('PER SIDE'), findsNothing, reason: 'still on the reverse tab');
    });
  });

  group('phone width', () {
    for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      testWidgets('both tabs fit 320 px with no overflow ($name, lb)', (tester) async {
        _lbTarget(700);
        await _open(tester, theme: theme);
        expect(tester.takeException(), isNull);

        await _openReverse(tester);
        for (var i = 0; i < 9; i++) {
          await _press(tester, _inc(45));
        }
        await _press(tester, _inc(2.5));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('860'), findsOneWidget);
      });

      testWidgets('both tabs fit 320 px with no overflow ($name, kg)', (tester) async {
        fit.plateTarget = 317.5;
        await _open(tester, theme: theme);
        expect(tester.takeException(), isNull);

        await _openReverse(tester);
        await _press(tester, _inc(25));
        await _press(tester, _inc(1.25));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('72.5'), findsOneWidget);
      });
    }
  });
}
