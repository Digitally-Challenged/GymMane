import 'dart:async' show unawaited;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/screens/places_screen.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/theme/plate_palette.dart';
import 'package:gymmane/widgets/plates/plate_disc.dart';
import 'package:gymmane/widgets/plates/plate_inventory_sheet.dart';
import 'package:gymmane/widgets/rolling_text.dart';
import 'package:gymmane/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _reset() {
  fit.setUnits('kg');
  fit.places.clear();
  fit.activePlaceId = '';
  fit.plateBar = null;
}

/// A barbell gym named "Garage", made through the same calls the app uses.
String _gym() => fit.addPlace('Garage', equipment: {'Barbell'});

/// Opens the inventory sheet from a button, the way the Places screen does.
Future<void> _open(WidgetTester tester, {double width = 360, double height = 1100}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlateInventory(context, fit.places.first),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The Places screen on a phone [width] px wide.
Future<void> _pumpPlaces(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: AnimatedBuilder(
        animation: fit,
        builder: (_, _) => const Scaffold(body: PlacesScreen()),
      ),
    ),
  );
}

Finder _disc(double size) => find.byWidgetPredicate((w) => w is PlateDisc && w.size == size);

Finder _inc(double size) =>
    find.descendant(of: _disc(size), matching: find.byKey(const ValueKey('plate-disc-inc')));

Finder _dec(double size) =>
    find.descendant(of: _disc(size), matching: find.byKey(const ValueKey('plate-disc-dec')));

PlateDisc _discWidget(WidgetTester tester, double size) => tester.widget<PlateDisc>(_disc(size));

Finder _row(String label, String glyph) =>
    find.descendant(of: find.widgetWithText(ToolRow, label), matching: find.text(glyph));

/// A stepper's value, which draws each character on its own so `find.text` cannot see it whole.
Finder _value(String text) => find.byWidgetPredicate((w) => w is RollingText && w.text == text);

Finder _swatch(Color c) => find.byKey(ValueKey('plate-swatch-${c.toARGB32()}'));

/// A widget test that saves at the end, so the save debounce timer is not left pending.
void _case(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      unawaited(fit.persistNow());
    }
  });
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    _reset();
  });

  group('colours', () {
    _case('long-pressing a disc and picking red makes the gym custom', (tester) async {
      fit.setUnits('lb');
      _gym();
      await _open(tester);
      expect(fit.places.first.customColours, isFalse);
      expect(_discWidget(tester, 45).colour, kPlateBlue);

      await tester.longPress(find.descendant(of: _disc(45), matching: find.text('45')));
      await tester.pumpAndSettle();
      expect(find.text('45 lb colour'), findsOneWidget, reason: 'the picker is titled with the plate');
      expect(_swatch(kPlateBlue), findsOneWidget);
      expect(
        tester.getSemantics(_swatch(kPlateBlue)).getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
        reason: "the plate's current colour is marked",
      );
      expect(
        tester.getSemantics(_swatch(kPlateRed)).getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse,
      );

      await _tap(tester, _swatch(kPlateRed));

      expect(find.text('45 lb colour'), findsNothing, reason: 'picking a colour closes the picker');
      final place = fit.places.first;
      expect(place.customColours, isTrue);
      final override = place.plateColours.entries.single;
      expect(override.key, closeTo(fit.fromDisplayWeight(45), 0.05), reason: 'stored in kg');
      expect(override.value, kPlateRed.toARGB32());
      expect(_discWidget(tester, 45).colour, kPlateRed);
      expect(_discWidget(tester, 35).colour, kPlateYellow, reason: 'the other plates keep their colour');
    });

    _case('the picker lays the eight colours out as two even rows of four', (tester) async {
      fit.setUnits('lb');
      _gym();
      await _open(tester, width: 402);
      await tester.longPress(find.descendant(of: _disc(45), matching: find.text('45')));
      await tester.pumpAndSettle();

      final rects = [for (final c in kPlateSwatches) tester.getRect(_swatch(c))];
      expect(rects, hasLength(8));
      final tops = rects.map((r) => r.top).toSet();
      expect(tops, hasLength(2), reason: 'a 402 px phone used to wrap 6 and 2');
      expect(rects.take(4).map((r) => r.top).toSet(), hasLength(1));
      expect(rects.skip(4).map((r) => r.top).toSet(), hasLength(1));
      for (var i = 0; i < 4; i++) {
        expect(rects[i + 4].left, rects[i].left, reason: 'column $i lines up across the rows');
      }
      for (final r in rects) {
        expect(r.width, greaterThanOrEqualTo(44));
        expect(r.height, greaterThanOrEqualTo(44));
      }
    });

    _case('a long press on the − or + button does not open the picker', (tester) async {
      _gym();
      await _open(tester);
      await tester.longPress(_inc(20));
      await tester.pumpAndSettle();
      expect(find.text('20 kg colour'), findsNothing);
    });

    _case('Coloured and Iron switch the preset and keep the overrides', (tester) async {
      final id = _gym();
      fit.setPlateColour(id, 20, kPlateRed);
      await _open(tester);
      expect(fit.places.first.customColours, isTrue);

      await _tap(tester, find.text('Iron'));
      var place = fit.places.first;
      expect(place.colourBase, PlateColourBase.iron);
      expect(place.customColours, isFalse);
      expect(place.plateColours, {20.0: kPlateRed.toARGB32()}, reason: 'overrides are kept');
      expect(_discWidget(tester, 20).colour, isNot(kPlateRed));

      await _tap(tester, find.text('Coloured'));
      expect(fit.places.first.colourBase, PlateColourBase.coloured);
      expect(fit.places.first.plateColours, {20.0: kPlateRed.toARGB32()});

      await _tap(tester, find.text('Custom'));
      place = fit.places.first;
      expect(place.customColours, isTrue, reason: 'Custom brings the overrides back');
      expect(_discWidget(tester, 20).colour, kPlateRed);
    });

    _case('Custom does nothing until a plate has its own colour', (tester) async {
      _gym();
      await _open(tester);

      await _tap(tester, find.text('Custom'));
      expect(fit.places.first.customColours, isFalse);
      expect(fit.places.first.colourBase, PlateColourBase.coloured);
    });

    _case('Custom reads as dimmed until a plate has its own colour', (tester) async {
      final handle = tester.ensureSemantics();
      _gym();
      await _open(tester);

      var custom = tester.getSemantics(find.bySemanticsLabel('Custom')).getSemanticsData();
      expect(custom.flagsCollection.isEnabled, Tristate.isFalse);
      expect(custom.hasAction(SemanticsAction.tap), isFalse);
      final coloured = tester.getSemantics(find.bySemanticsLabel('Coloured')).getSemanticsData();
      expect(coloured.flagsCollection.isEnabled, isNot(Tristate.isFalse), reason: 'only Custom is off');

      fit.setPlateColour(fit.places.first.id, 20, kPlateRed);
      await tester.pumpAndSettle();
      custom = tester.getSemantics(find.bySemanticsLabel('Custom')).getSemanticsData();
      expect(custom.flagsCollection.isEnabled, isNot(Tristate.isFalse));
      handle.dispose();
    });
  });

  group('stock', () {
    _case('the reset keeps collars and colours', (tester) async {
      final id = _gym();
      fit.setPlatePairs(id, 20, 2);
      fit.setPlatePairs(id, 25, 1);
      fit.setPlaceBar(id, 15);
      fit.setPlaceCollar(id, 2.5);
      fit.setPlaceColourBase(id, PlateColourBase.iron);
      fit.setPlateColour(id, 20, kPlateRed);
      await _open(tester);
      expect(find.text('∞'), findsNothing);

      await _tap(tester, find.text('Everything available'));

      final place = fit.places.first;
      expect(place.plates, isEmpty);
      expect(place.bar, isNull);
      expect(place.collarKg, 2.5);
      expect(place.colourBase, PlateColourBase.iron);
      expect(place.customColours, isTrue);
      expect(place.plateColours, {20.0: kPlateRed.toARGB32()});
      expect(find.text('Everything available'), findsNothing, reason: 'nothing left to reset');
      expect(find.text('∞'), findsNWidgets(7));
    });

    _case('an empty stock shows ∞ on every disc, none dimmed', (tester) async {
      _gym();
      await _open(tester);

      expect(find.byType(PlateDisc), findsNWidgets(7));
      expect(find.text('∞'), findsNWidgets(7));
      for (final size in fit.plateSizes) {
        expect(_discWidget(tester, size).dimmed, isFalse, reason: '$size');
        expect(_discWidget(tester, size).count, isNull, reason: '$size');
      }
      expect(find.text('Everything available'), findsNothing);
    });

    _case('with stock, a size with no pairs is dimmed at 0', (tester) async {
      final id = _gym();
      fit.setPlatePairs(id, 25, 2);
      await _open(tester);

      expect(_discWidget(tester, 25).count, 2);
      expect(_discWidget(tester, 25).dimmed, isFalse);
      for (final size in fit.plateSizes.where((s) => s != 25)) {
        expect(_discWidget(tester, size).count, 0, reason: '$size');
        expect(_discWidget(tester, size).dimmed, isTrue, reason: '$size');
        expect(_discWidget(tester, size).onDec, isNull, reason: 'nothing to take away at $size');
      }
      expect(find.text('∞'), findsNothing);
    });

    _case('a lb gym reads its kg-stored stock back as 45', (tester) async {
      fit.setUnits('lb');
      final id = _gym();
      fit.setPlatePairs(id, fit.fromDisplayWeight(45), 3);
      await _open(tester);

      expect(_discWidget(tester, 45).count, 3);
      expect(_discWidget(tester, 45).dimmed, isFalse);
      expect(_discWidget(tester, 35).dimmed, isTrue);
    });

    _case('+ and − on a disc edit the pairs, and the last − gives back everything', (tester) async {
      _gym();
      await _open(tester);

      await _tap(tester, _inc(20));
      expect(fit.platePairs(fit.places.first, 20), 1);
      expect(_discWidget(tester, 20).count, 1);
      expect(_discWidget(tester, 25).dimmed, isTrue);

      await _tap(tester, _inc(20));
      expect(fit.platePairs(fit.places.first, 20), 2);

      await _tap(tester, _dec(20));
      await _tap(tester, _dec(20));
      expect(fit.places.first.plates, isEmpty);
      expect(find.text('∞'), findsNWidgets(7));
    });
  });

  group('bar and collars', () {
    _case('the bar stepper moves by the plate step', (tester) async {
      _gym();
      await _open(tester);
      expect(_value('20 kg'), findsOneWidget);

      await _tap(tester, _row('Bar weight', '+'));
      expect(fit.places.first.bar, 22.5);
      expect(_value('22.5 kg'), findsOneWidget);
    });

    _case('the collars stepper changes collarKg in kg for a lb user', (tester) async {
      fit.setUnits('lb');
      _gym();
      await _open(tester);
      expect(_value('0 lb'), findsOneWidget);

      await _tap(tester, _row('Collars (each)', '+'));
      expect(fit.places.first.collarKg, closeTo(0.227, 1e-9), reason: '0.5 lb is 0.227 kg');
      expect(_value('0.5 lb'), findsOneWidget);

      await _tap(tester, _row('Collars (each)', '+'));
      expect(fit.places.first.collarKg, closeTo(0.454, 1e-9), reason: '1 lb is 0.454 kg');
      expect(_value('1 lb'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await _tap(tester, _row('Collars (each)', '–'));
      }
      expect(fit.places.first.collarKg, 0, reason: 'never below zero');
      expect(_value('0 lb'), findsOneWidget);
    });

    _case('the collars stepper moves a kg user by a quarter kilo', (tester) async {
      _gym();
      await _open(tester);

      await _tap(tester, _row('Collars (each)', '+'));
      await _tap(tester, _row('Collars (each)', '+'));
      expect(fit.places.first.collarKg, 0.5);
      expect(_value('0.5 kg'), findsOneWidget);
    });
  });

  group('entry point', () {
    _case('the Places screen opens it and Done closes it', (tester) async {
      _gym();
      await _pumpPlaces(tester, width: 360);

      expect(tester.takeException(), isNull, reason: 'the empty stock reads "Everything available"');
      await _tap(tester, find.text('Plates and bar'));
      expect(find.byType(PlateDisc), findsNWidgets(7));

      await _tap(tester, find.text('DONE'));
      expect(find.byType(PlateDisc), findsNothing);
    });

    _case('the Plates and bar row fits a 320 px phone', (tester) async {
      _gym();
      await _pumpPlaces(tester, width: 320);

      expect(find.text('Everything available'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _case('a short Plates and bar value keeps the caret on the trailing edge', (tester) async {
      final id = _gym();
      fit.setPlatePairs(id, 20, 1);
      fit.setPlatePairs(id, 10, 1);
      fit.setPlatePairs(id, 5, 1);
      await _pumpPlaces(tester, width: 360);

      expect(find.text('3 sizes'), findsOneWidget);
      final row = find.ancestor(of: find.text('Plates and bar'), matching: find.byType(Row)).first;
      final caret = find.descendant(of: row, matching: find.byType(Icon)).last;
      expect(tester.getTopRight(caret).dx, tester.getTopRight(row).dx);
    });

    _case('a small phone scrolls to Done without overflowing', (tester) async {
      _gym();
      await _open(tester, width: 320, height: 568);
      expect(tester.takeException(), isNull);

      final done = find.text('DONE');
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      await _tap(tester, done);
      expect(find.byType(PlateDisc), findsNothing);
    });
  });
}
