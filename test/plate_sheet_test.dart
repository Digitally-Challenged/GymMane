import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/screens/session_screen.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/l10n/l10n.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/widgets/plates/barbell_view.dart';
import 'package:gymmane/widgets/plates/plate_sheet.dart';
import 'package:gymmane/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(375, 667);

void _lb() {
  fit.setUnits('lb');
  unawaited(fit.persistNow());
  fit.places.clear();
  fit.activePlaceId = '';
}

/// Opens the between-sets sheet from a button, the way a set row does.
Future<void> _open(
  WidgetTester tester,
  double target, {
  double? startBar,
  double collars = 0,
  double? previousDisplay,
  Size size = _phone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlateSheet(
              context,
              target,
              startBar: startBar,
              collars: collars,
              previousDisplay: previousDisplay,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// A running bench session whose sets weigh [lbs]; the first [done] of them are logged.
void _startBench(List<double> lbs, {required int done}) {
  fit.sessionLayout = 'cards';
  final routine = fit.createRoutine('Bench');
  fit.toggleRoutineExercise(routine, 'EIeI8Vf');
  fit.startRoutine(fit.routines.first);
  fit.endCountdown();
  while (fit.session!.exercises.first.sets.length < lbs.length) {
    fit.addSet(0);
  }
  final sets = fit.session!.exercises.first.sets;
  for (var i = 0; i < lbs.length; i++) {
    sets[i].weight = fit.fromDisplayWeight(lbs[i]);
    sets[i].done = i < done;
  }
}

/// Opens the sheet by tapping the plate hint under the sets.
Future<void> _tapPlateHint(WidgetTester tester) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListenableBuilder(listenable: fit, builder: (_, _) => SessionScreen()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  final hint = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == t.toolTitle('plate'));
  await tester.ensureVisible(hint);
  await tester.tap(hint);
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _changeLine() => find.textContaining('each side');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    _lb();
  });

  group('change line', () {
    testWidgets('the sheet tells you what to add since the last set', (tester) async {
      await _open(tester, 235, previousDisplay: 225);
      expect(find.text('Add 5 each side'), findsOneWidget);
    });

    testWidgets('it tells you what to take off when the weight drops', (tester) async {
      await _open(tester, 225, previousDisplay: 235);
      expect(find.text('Take off 5 each side'), findsOneWidget);
    });

    testWidgets('it names both when one plate swaps for another', (tester) async {
      await _open(tester, 245, previousDisplay: 235);
      expect(find.text('Take off 5, add 10 each side'), findsOneWidget);
    });

    testWidgets('no change line on the first set or an unchanged weight', (tester) async {
      await _open(tester, 235);
      expect(find.byType(BarbellView), findsOneWidget);
      expect(_changeLine(), findsNothing);

      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      await _open(tester, 235, previousDisplay: 235);
      expect(find.byType(BarbellView), findsOneWidget);
      expect(_changeLine(), findsNothing);
    });

    testWidgets('no change line when a different weight loads the same plates', (tester) async {
      await _open(tester, 226, previousDisplay: 225);
      expect(_changeLine(), findsNothing);
    });

    testWidgets('going back to the empty bar says what comes off', (tester) async {
      await _open(tester, 45, previousDisplay: 135);
      expect(find.text('Take off 45 each side'), findsOneWidget);
      expect(find.text('Just the bar.'), findsOneWidget);
    });

    testWidgets('collars count towards the change', (tester) async {
      // 87.5 a side before (45 · 35 · 5 · 2.5), 92.5 now (45 ×2 · 2.5); without collars it would be "Add 5".
      await _open(tester, 235, previousDisplay: 225, collars: 5);
      expect(find.text('Take off 35 · 5, add 45 each side'), findsOneWidget);
    });

    testWidgets('weights stored in kilos still land on the plates they were set to', (tester) async {
      await _open(tester, fit.toDisplayWeight(142.88), previousDisplay: fit.toDisplayWeight(102.06));
      expect(find.text('Add 45 each side'), findsOneWidget);
      expect(find.text('45 ×3'), findsOneWidget);
    });
  });

  group('bar picker', () {
    testWidgets('picking another bar recomputes the plates and the change', (tester) async {
      await _open(tester, 235, startBar: 45, previousDisplay: 225);
      expect(find.text('Add 5 each side'), findsOneWidget);

      await tester.tap(find.text('35 lb'));
      await tester.pump();
      expect(find.text('Take off 5, add 10 each side'), findsOneWidget, reason: '100 a side now, 95 before');
      expect(find.text('Add 5 each side'), findsNothing);
    });

    testWidgets('the sheet starts on the bar it was given', (tester) async {
      await _open(tester, 225, startBar: 35);
      expect(find.text('45 ×2'), findsOneWidget, reason: '95 a side on a 35 lb bar');
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('a start bar that is not an option is added to the row', (tester) async {
      await _open(tester, 225, startBar: 25);
      expect(find.text('25 lb'), findsOneWidget);
      expect(find.text('45 lb'), findsOneWidget);
      expect(find.text('45 ×2'), findsOneWidget);
      expect(find.text('10'), findsOneWidget, reason: '100 a side on a 25 lb bar is 45 ×2 and 10');
    });

    testWidgets('a start bar that is already an option is not doubled', (tester) async {
      await _open(tester, 225, startBar: 45);
      expect(find.text('45 lb'), findsOneWidget);
    });

    testWidgets('collars come off the plates', (tester) async {
      await _open(tester, 225, collars: 5);
      expect(find.text('35'), findsOneWidget, reason: '87.5 a side is 45, 35, 5 and 2.5');
      expect(find.text('45 ×2'), findsNothing);
    });
  });

  group('shape', () {
    testWidgets('it says the closest load when the target cannot be reached', (tester) async {
      await _open(tester, 226);
      expect(find.text('Closest you can load: 225 lb'), findsOneWidget);
    });

    testWidgets('Done closes the sheet', (tester) async {
      await _open(tester, 225);
      expect(find.byType(BarbellView), findsOneWidget);
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      expect(find.byType(BarbellView), findsNothing);
    });

    testWidgets('a 6-plate load with a change line fits a 667 pt phone without scrolling', (tester) async {
      // 45 ×3 · 35 · 5 · 2.5 a side on a 25 lb bar (added to the row), after 45 · 10 · 5 · 2.5.
      await _open(tester, 380, startBar: 25, previousDisplay: 150);
      expect(tester.takeException(), isNull);
      expect(find.text('Take off 10, add 45 ×2 · 35 each side'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent,
        0,
        reason: 'nothing to scroll to',
      );
      expect(find.text('DONE').hitTestable(), findsOneWidget);
      final button = tester.getRect(find.byType(PrimaryButton));
      expect(button.bottom, lessThanOrEqualTo(_phone.height));
      expect(tester.getRect(find.byType(BarbellView)).top, greaterThan(0));
    });
  });

  group('session row', () {
    setUp(() {
      fit.sessions.clear();
      fit.routines.clear();
      fit.onboarded = true;
      fit.demoSize = 'off';
    });
    tearDown(() => fit.saveAndExit());

    testWidgets('the sheet compares the next set with the one above it', (tester) async {
      await tester.runAsync(() async {
        _startBench([225, 235, 245], done: 1);
        await _tapPlateHint(tester);
        expect(find.byType(BarbellView), findsOneWidget);
        expect(find.text('Add 5 each side'), findsOneWidget);
      });
    });

    testWidgets('with every set done it opens on the last set, against the one above', (tester) async {
      await tester.runAsync(() async {
        _startBench([225, 235, 245], done: 3);
        await _tapPlateHint(tester);
        expect(find.text('Take off 5, add 10 each side'), findsOneWidget);
      });
    });

    testWidgets('the first set has nothing to compare with', (tester) async {
      await tester.runAsync(() async {
        _startBench([225, 235, 245], done: 0);
        await _tapPlateHint(tester);
        expect(find.byType(BarbellView), findsOneWidget);
        expect(_changeLine(), findsNothing);
      });
    });

    testWidgets('the gym collars come off the plates', (tester) async {
      await tester.runAsync(() async {
        final gym = fit.addPlace('Home');
        fit.setActivePlace(gym);
        fit.setPlaceCollar(gym, fit.fromDisplayWeight(2.5));
        _startBench([225, 235], done: 1);
        await _tapPlateHint(tester);
        expect(find.text('Take off 35 · 5, add 45 each side'), findsOneWidget);
      });
    });
  });
}
