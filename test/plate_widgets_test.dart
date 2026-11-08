import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/plate_math.dart';
import 'package:gymmane/theme/app_colors.dart';
import 'package:gymmane/theme/app_theme.dart';
import 'package:gymmane/theme/plate_palette.dart';
import 'package:gymmane/widgets/plates/barbell_view.dart';
import 'package:gymmane/widgets/plates/plate_chips.dart';
import 'package:gymmane/widgets/plates/plate_disc.dart';

Color _colourOf(double w) => w == 45 ? kPlateBlue : (w == 10 ? kPlateWhite : kPlateGrey);

Widget _host(Widget child, {double width = 320, ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// A plate on the bar is keyed `plate-<size>-<index>`; the disc's `plate-disc-*` buttons are not plates.
final _plateKey = RegExp(r'^plate-\d+(\.\d+)?-\d+$');

bool _isPlate(Widget w) {
  final k = w.key;
  return k is ValueKey<String> && _plateKey.hasMatch(k.value);
}

Finder _plates() => find.byWidgetPredicate(_isPlate);

/// The plates left to right, as screen rectangles.
List<Rect> _plateRects(WidgetTester tester) {
  final rects = [
    for (final e in _plates().evaluate())
      tester.getTopLeft(find.byWidget(e.widget)) & tester.getSize(find.byWidget(e.widget)),
  ];
  return rects..sort((a, b) => a.left.compareTo(b.left));
}

BoxDecoration _decorationOf(WidgetTester tester, Finder f) =>
    tester.widget<DecoratedBox>(f).decoration as BoxDecoration;

void main() {
  const heavy = <PlateCount>[(weight: 45, count: 7), (weight: 10, count: 1), (weight: 2.5, count: 1)];

  group('BarbellView', () {
    for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      testWidgets('a 700 lb bar draws without overflow at 320 wide ($name)', (tester) async {
        await tester.pumpWidget(
          _host(
            const BarbellView(perSide: heavy, colourOf: _colourOf, largest: 45),
            theme: theme,
          ),
        );
        expect(tester.takeException(), isNull);

        final view = tester.getRect(find.byType(BarbellView));
        final rects = _plateRects(tester);
        expect(rects, hasLength(9), reason: '7 + 1 + 1 plates on the sleeve');
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(view.left));
          expect(r.right, lessThanOrEqualTo(view.right));
          expect(r.top, greaterThanOrEqualTo(view.top));
          expect(r.bottom, lessThanOrEqualTo(view.bottom));
        }
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right), reason: 'plates must not overlap');
        }
      });
    }

    testWidgets('plates start 16 wide and shrink evenly to stay on the sleeve', (tester) async {
      await tester.pumpWidget(
        _host(const BarbellView(perSide: [(weight: 45, count: 2)], colourOf: _colourOf, largest: 45)),
      );
      expect(_plateRects(tester).map((r) => r.width), everyElement(closeTo(16, 1e-6)));

      await tester.pumpWidget(
        _host(const BarbellView(perSide: [(weight: 45, count: 30)], colourOf: _colourOf, largest: 45)),
      );
      expect(tester.takeException(), isNull);
      final rects = _plateRects(tester);
      expect(rects, hasLength(30));
      expect(rects.first.width, lessThan(16));
      final widths = rects.map((r) => r.width);
      expect(
        widths.reduce(math.max) - widths.reduce(math.min),
        lessThan(1e-6),
        reason: 'every plate shrinks by the same amount',
      );
      expect(rects.last.right, lessThanOrEqualTo(tester.getRect(find.byType(BarbellView)).right));
    });

    testWidgets('plate height follows weight and the largest plate fills the height', (tester) async {
      await tester.pumpWidget(
        _host(const BarbellView(perSide: heavy, colourOf: _colourOf, largest: 45, height: 100)),
      );
      final heights = {
        for (final e in _plates().evaluate())
          (e.widget.key! as ValueKey<String>).value: tester.getSize(find.byWidget(e.widget)).height,
      };
      expect(tester.getSize(find.byType(BarbellView)).height, 100);
      expect(heights['plate-45-0'], closeTo(100, 0.01));
      expect(heights['plate-10-7'], closeTo(100 * (0.45 + 0.55 * 10 / 45), 0.01));
      expect(heights['plate-2.5-8'], closeTo(100 * (0.45 + 0.55 * 2.5 / 45), 0.01));
    });

    testWidgets('a plate larger than the stated largest is clamped to the height', (tester) async {
      await tester.pumpWidget(
        _host(const BarbellView(perSide: [(weight: 90, count: 1)], colourOf: _colourOf, largest: 45)),
      );
      expect(tester.getSize(_plates()).height, 120);
    });

    testWidgets('only light plates get a hairline outline', (tester) async {
      await tester.pumpWidget(_host(const BarbellView(perSide: heavy, colourOf: _colourOf, largest: 45)));
      final blue = _decorationOf(tester, find.byKey(const ValueKey('plate-45-0')));
      final white = _decorationOf(tester, find.byKey(const ValueKey('plate-10-7')));
      expect(blue.color, kPlateBlue);
      expect(blue.border, isNull);
      expect(white.color, kPlateWhite);
      final side = (white.border! as Border).top;
      expect(side.width, 1);
      expect(side.color, GymColors.light.border);
    });

    testWidgets('the collar block is drawn only when asked for', (tester) async {
      await tester.pumpWidget(
        _host(const BarbellView(perSide: [(weight: 45, count: 1)], colourOf: _colourOf, largest: 45)),
      );
      expect(find.byKey(const ValueKey('barbell-collar')), findsOneWidget);

      await tester.pumpWidget(
        _host(
          const BarbellView(
            perSide: [(weight: 45, count: 1)],
            colourOf: _colourOf,
            largest: 45,
            collar: false,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('barbell-collar')), findsNothing);
    });

    testWidgets('an empty bar draws the shaft and sleeve with no plates', (tester) async {
      await tester.pumpWidget(_host(const BarbellView(perSide: [], colourOf: _colourOf, largest: 45)));
      expect(tester.takeException(), isNull);
      expect(_plates(), findsNothing);
      expect(find.byKey(const ValueKey('barbell-sleeve')), findsOneWidget);
    });
  });

  group('PlateDisc', () {
    Finder dec() => find.byKey(const ValueKey('plate-disc-dec'));
    Finder inc() => find.byKey(const ValueKey('plate-disc-inc'));

    testWidgets("a disc's buttons fire and the hub shows ∞ for unlimited stock", (tester) async {
      var decs = 0, incs = 0, longs = 0;
      Widget disc(int? count) => _host(
        width: 96,
        PlateDisc(
          size: 45,
          colour: kPlateBlue,
          count: count,
          onDec: () => decs++,
          onInc: () => incs++,
          onLongPress: () => longs++,
        ),
      );

      await tester.pumpWidget(disc(2));
      expect(find.text('45'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('∞'), findsNothing);

      await tester.tap(dec());
      await tester.tap(inc());
      await tester.tap(inc());
      expect((decs, incs), (1, 2));

      await tester.longPress(find.text('45'));
      expect(longs, 1);

      await tester.pumpWidget(disc(null));
      expect(find.text('∞'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      await tester.tap(inc());
      expect(incs, 3, reason: 'unlimited stock can still be raised');
    });

    testWidgets('the − and + hit areas are at least 44 × 44', (tester) async {
      for (final width in [96.0, 88.0, 120.0]) {
        await tester.pumpWidget(
          _host(
            width: width,
            PlateDisc(size: 45, colour: kPlateBlue, count: 1, onDec: () {}, onInc: () {}),
          ),
        );
        for (final f in [dec(), inc()]) {
          final s = tester.getSize(f);
          expect(s.width, greaterThanOrEqualTo(44), reason: 'width at $width');
          expect(s.height, greaterThanOrEqualTo(44), reason: 'height at $width');
          final r = tester.getRect(f);
          final disc = tester.getRect(find.byType(PlateDisc)).inflate(0.01);
          expect(
            r.left >= disc.left && r.top >= disc.top && r.right <= disc.right && r.bottom <= disc.bottom,
            isTrue,
            reason: 'the hit area must sit inside the disc so every tap lands',
          );
        }
      }
    });

    testWidgets('a button with no callback is inert and reads as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      var incs = 0;
      await tester.pumpWidget(
        _host(width: 96, PlateDisc(size: 45, colour: kPlateBlue, count: 0, onDec: null, onInc: () => incs++)),
      );

      await tester.tap(dec());
      expect(incs, 0, reason: 'tapping the disabled − must not reach the + callback');
      await tester.tap(inc());
      expect(incs, 1, reason: 'the + next to it still works');

      SemanticsData semantics(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      final minus = semantics('Decrease 45');
      expect(minus.flagsCollection.isEnabled, Tristate.isFalse);
      expect(minus.hasAction(SemanticsAction.tap), isFalse);
      final plus = semantics('Increase 45');
      expect(plus.flagsCollection.isEnabled, Tristate.isTrue);
      expect(plus.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('the − and + buttons are labelled for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(width: 96, PlateDisc(size: 2.5, colour: kPlateGrey, count: 1, onDec: () {}, onInc: () {})),
      );
      expect(find.bySemanticsLabel('Decrease 2.5'), findsOneWidget);
      expect(find.bySemanticsLabel('Increase 2.5'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ink is whichever of dark and white contrasts more with the plate', (tester) async {
      const dark = Color(0xFF1A1713);
      const white = Color(0xFFFFFFFF);
      final cases = <(String, Color, Color)>[
        ('grey', const Color(0xFF777777), white),
        ('blue', kPlateBlue, white),
        ('white', const Color(0xFFEEEEEE), dark),
        ('yellow', kPlateYellow, dark),
        ('green', kPlateGreen, dark),
      ];
      for (final (name, plate, ink) in cases) {
        await tester.pumpWidget(
          _host(width: 96, PlateDisc(size: 45, colour: plate, count: 3, onDec: () {}, onInc: () {})),
        );
        expect(tester.widget<Text>(find.text('45')).style!.color, ink, reason: '$name plate label');
        expect(tester.widget<Text>(find.text('−')).style!.color, ink, reason: '$name plate − glyph');
      }
    });

    testWidgets('dimmed discs sit at 35% opacity', (tester) async {
      double opacity() => tester
          .widget<Opacity>(find.descendant(of: find.byType(PlateDisc), matching: find.byType(Opacity)))
          .opacity;

      await tester.pumpWidget(
        _host(width: 96, PlateDisc(size: 45, colour: kPlateBlue, count: 1, onDec: () {}, onInc: () {})),
      );
      expect(opacity(), 1);

      await tester.pumpWidget(
        _host(
          width: 96,
          PlateDisc(size: 45, colour: kPlateBlue, count: 1, onDec: () {}, onInc: () {}, dimmed: true),
        ),
      );
      expect(opacity(), closeTo(0.35, 1e-9));
    });
  });

  group('PlateChips', () {
    testWidgets('each size is a chip with its swatch and count', (tester) async {
      await tester.pumpWidget(
        _host(
          const PlateChips(perSide: [(weight: 45, count: 2), (weight: 25, count: 1)], colourOf: _colourOf),
        ),
      );
      expect(find.text('45 ×2'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      final swatches = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == kPlateBlue,
      );
      expect(swatches, findsOneWidget);
    });

    testWidgets('chips wrap instead of overflowing', (tester) async {
      await tester.pumpWidget(
        _host(
          width: 160,
          const PlateChips(
            perSide: [
              (weight: 45, count: 7),
              (weight: 35, count: 2),
              (weight: 25, count: 2),
              (weight: 10, count: 1),
              (weight: 5, count: 1),
              (weight: 2.5, count: 1),
            ],
            colourOf: _colourOf,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(PlateChips)).width, lessThanOrEqualTo(160));
    });

    testWidgets('no plates draws nothing', (tester) async {
      await tester.pumpWidget(_host(const PlateChips(perSide: [], colourOf: _colourOf)));
      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('plateSumLine', () {
    test('the sum line reads like the mockup', () {
      expect(
        plateSumLine(
          bar: 45,
          collars: 0,
          perSide: const [(weight: 45, count: 2), (weight: 25, count: 1)],
          total: 275,
        ),
        '45 bar + 2 × (45 + 45 + 25) = 275',
      );
    });

    test('collars get their own term', () {
      expect(
        plateSumLine(
          bar: 45,
          collars: 5,
          perSide: const [(weight: 45, count: 2), (weight: 25, count: 1)],
          total: 280,
        ),
        '45 bar + 5 collars + 2 × (45 + 45 + 25) = 280',
      );
    });

    test('fractional plates and totals keep their decimals', () {
      expect(
        plateSumLine(
          bar: 20,
          collars: 0,
          perSide: const [(weight: 20, count: 1), (weight: 1.25, count: 1)],
          total: 62.5,
        ),
        '20 bar + 2 × (20 + 1.25) = 62.5',
      );
    });
  });
}
