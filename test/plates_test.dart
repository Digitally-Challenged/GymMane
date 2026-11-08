import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/place.dart';
import 'package:gymmane/models/plate_math.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/plate_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PlateCount> _plates(List<(double, int)> rows) =>
    [for (final r in rows) (weight: r.$1, count: r.$2)];

String _id() {
  final id = fit.addPlace('Home', equipment: {'Barbell'});
  fit.setActivePlace(id);
  return id;
}

void _reset() {
  fit.setUnits('kg');
  fit.places.clear();
  fit.activePlaceId = '';
  fit.exerciseBar.clear();
  fit.plateBar = null;
  fit.plateTarget = 100;
  fit.clearReverse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    _reset();
  });

  tearDown(() async {
    _reset();
    await fit.persistNow();
  });

  group('plateChange', () {
    test('225 to 235 lb only adds a 5', () {
      fit.setUnits('lb');
      final c = plateChange(fit.platesPerSide(225, 45), fit.platesPerSide(235, 45));
      expect(c.off, isEmpty);
      expect(c.on, _plates([(5, 1)]));
    });

    test('185 to 205 lb swaps the 25 for a 35', () {
      fit.setUnits('lb');
      final c = plateChange(fit.platesPerSide(185, 45), fit.platesPerSide(205, 45));
      expect(c.off, _plates([(25, 1)]));
      expect(c.on, _plates([(35, 1)]));
    });

    test('equal loadings change nothing', () {
      final same = _plates([(45, 2), (25, 1)]);
      final c = plateChange(same, _plates([(45, 2), (25, 1)]));
      expect(c.off, isEmpty);
      expect(c.on, isEmpty);
    });

    test('from nothing to two 45s puts both on', () {
      final c = plateChange(const [], _plates([(45, 2)]));
      expect(c.off, isEmpty);
      expect(c.on, _plates([(45, 2)]));
    });

    test('both sides come back heaviest first', () {
      final c = plateChange(_plates([(2.5, 1), (10, 1), (25, 1)]), _plates([(5, 1), (20, 1), (15, 1)]));
      expect(c.off.map((p) => p.weight), [25, 10, 2.5]);
      expect(c.on.map((p) => p.weight), [20, 15, 5]);
    });

    test('a smaller count on the same plate is a partial take-off', () {
      final c = plateChange(_plates([(45, 3)]), _plates([(45, 1)]));
      expect(c.off, _plates([(45, 2)]));
      expect(c.on, isEmpty);
    });
  });

  test('plateList reads 45 ×2 · 25', () {
    expect(plateList(_plates([(45, 2), (25, 1)])), '45 ×2 · 25');
    expect(plateList(const []), '');
  });

  group('collars', () {
    test('collars eat into the plates, never below zero', () {
      final id = _id();
      fit.setPlaceCollar(id, 2.5);
      final c = fit.collarsDisplay;
      expect(c, 5);

      final parts = fit.platesPerSide(100, 20, collars: c);
      expect(parts, _plates([(25, 1), (10, 1), (2.5, 1)]));
      expect(fit.loadableTotal(100, 20, collars: c), 100);

      expect(fit.platesPerSide(22, 20, collars: c), isEmpty);
      expect(fit.platesPerSide(25, 20, collars: c), isEmpty);
      expect(fit.loadableTotal(22, 20, collars: c), 25, reason: 'the bar and collars is the floor');
    });

    test('the plate tool and the 1RM share count the gym collars', () {
      final id = _id();
      fit.setPlaceCollar(id, 2.5);
      fit.plateBar = 20;
      fit.plateTarget = 100;
      expect(fit.plateBreakdown, _plates([(25, 1), (10, 1), (2.5, 1)]));

      fit.setPlaceCollar(id, 1);
      fit.rmWeight = 120;
      fit.rmReps = 15;
      fit.rmPct = 50;
      expect(fit.rmAtPct, 89.5, reason: '90 kg minus collars lands on 89.5 with these plates');
    });

    test('exercises with their own bar never get collars', () {
      final id = _id();
      fit.setPlaceCollar(id, 2.5);
      fit.setExerciseBar('legpress', 0);

      expect(fit.collarsFor('legpress', equipment: 'Machine'), 0);
      expect(fit.collarsFor('squat'), 5);
      expect(fit.collarsFor('curl', equipment: 'Dumbbell'), 0);
      expect(fit.plateHint('Machine', 150, id: 'legpress'), '25×3');
      expect(fit.plateHint('Barbell', 100, id: 'squat'), '25 · 10 · 2.5');
    });

    test('collars follow the display unit, both counted', () {
      final id = _id();
      fit.setPlaceCollar(id, 1.134);
      fit.setUnits('lb');
      expect(fit.collarsDisplay, 5);
    });

    test('collars are clamped to 0-10 kg and persisted', () {
      final id = _id();
      fit.setPlaceCollar(id, 99);
      expect(fit.places.single.collarKg, 10);
      fit.setPlaceCollar(id, -3);
      expect(fit.places.single.collarKg, 0);
      fit.setPlaceCollar(id, 1.23456);
      expect(fit.places.single.collarKg, 1.235);
      expect(fit.placeCollarKg, 1.235);
    });

    test('no active gym means no collars', () {
      expect(fit.placeCollarKg, 0);
      expect(fit.collarsDisplay, 0);
    });
  });

  group('bar', () {
    test('a bar left on the gym default follows the gym, an override wins', () {
      final id = _id();
      fit.setPlaceBar(id, 15);
      expect(fit.plateBar, isNull);
      expect(fit.plateBarDisplay, 15);

      fit.setPlateBar(20);
      expect(fit.plateBarDisplay, 20);
      fit.plateBar = null;
      expect(fit.plateBarDisplay, 15);
    });

    test('the gym bar joins the options when it is not one already', () {
      expect(fit.plateBarOptions, [20, 15, 10]);
      final id = _id();
      fit.setPlaceBar(id, 12);
      expect(fit.plateBarOptions, [20, 15, 12, 10]);
      fit.setPlaceBar(id, 25);
      expect(fit.plateBarOptions, [25, 20, 15, 10]);
      fit.setUnits('lb');
      expect(fit.plateBarOptions.first, 55.1);
    });
  });

  group('bar and units', () {
    test('changing units drops the picked bar for the gym default', () {
      final id = _id();
      fit.setPlaceBar(id, 12);
      fit.plateBar = 15.875;
      fit.setUnits('lb');
      expect(fit.plateBar, isNull);
      expect(fit.plateBarDisplay, fit.defaultBar);
      expect(fit.plateBarDisplay, 26.5);
    });

    test('picking the unit already in use keeps the picked bar', () {
      fit.plateBar = 15;
      fit.setUnits('kg');
      expect(fit.plateBar, 15);
      expect(fit.plateBarDisplay, 15);
    });
  });

  group('stock sizes', () {
    test('a stocked 1.25 kg plate stays 1.25', () {
      final id = _id();
      fit.setPlatePairs(id, 1.25, 2);
      fit.setPlatePairs(id, 20, 4);
      expect(fit.plateStockDisplay!.keys, containsAll([1.25, 20.0]));
      expect(fit.platesPerSide(22.5, 20), _plates([(1.25, 1)]));
    });

    test('every standard size keeps its display value through kg storage', () {
      for (final unit in ['kg', 'lb']) {
        fit.setUnits(unit);
        fit.places.clear();
        final id = _id();
        for (final size in fit.plateSizes) {
          fit.setPlatePairs(id, fit.fromDisplayWeight(size), 1);
        }
        expect(fit.plateStockDisplay!.keys.toSet(), fit.plateSizes.toSet(), reason: unit);
      }
    });
  });

  group('reverse', () {
    test('reverse total adds bar, collars and both sides', () {
      fit.setUnits('lb');
      expect(fit.plateBarDisplay, 45);
      fit.bumpReverse(45, 1);
      fit.bumpReverse(35, 1);
      fit.bumpReverse(5, 1);
      expect(fit.reverseTotal, 215);
      fit.clearReverse();
      expect(fit.reverseTotal, 45);
      expect(fit.reverseCounts, isEmpty);
    });

    test('collars count in the reverse total', () {
      final id = _id();
      fit.setPlaceCollar(id, 2.5);
      fit.bumpReverse(25, 2);
      expect(fit.reverseTotal, 20 + 5 + 2 * 25 * 2);
    });

    test('the count floors at zero and has no ceiling', () {
      fit.bumpReverse(25, -1);
      expect(fit.reverseCounts[25] ?? 0, 0);
      fit.bumpReverse(25, 40);
      expect(fit.reverseCounts[25], 40);
      fit.bumpReverse(25, -41);
      expect(fit.reverseCounts[25] ?? 0, 0);
      expect(fit.reverseCounts, isEmpty);
    });

    test('changing units clears the reverse counts', () {
      fit.setUnits('lb');
      fit.bumpReverse(45, 2);
      fit.bumpReverse(2.5, 1);
      expect(fit.reverseCounts, isNotEmpty);
      fit.setUnits('kg');
      expect(fit.reverseCounts, isEmpty);
      expect(fit.reverseTotal, 20);
    });

    test('picking the unit already in use keeps the counts', () {
      fit.bumpReverse(25, 1);
      fit.setUnits('kg');
      expect(fit.reverseCounts[25], 1);
    });
  });

  group('GymPlace JSON', () {
    test('old place JSON loads as coloured with no collars', () {
      final p = GymPlace.fromJson({'id': 'a', 'n': 'Home', 'e': ['Barbell']});
      expect(p.collarKg, 0);
      expect(p.colourBase, PlateColourBase.coloured);
      expect(p.customColours, isFalse);
      expect(p.plateColours, isEmpty);
    });

    test('defaults write no new keys', () {
      final json = GymPlace.fromJson({'id': 'a', 'n': 'Home', 'e': ['Barbell']}).toJson();
      expect(json.keys.toSet(), {'id', 'n', 'e'});
    });

    test('a place with every new field survives toJson and fromJson', () {
      final original = GymPlace(
        id: 'a',
        name: 'Home',
        equipment: {'Barbell'},
        plates: {20.0: 2},
        bar: 15,
        collarKg: 1.25,
        colourBase: PlateColourBase.iron,
        customColours: true,
        plateColours: {20.412: 0xFFD9473B, 1.25: 0xFF3BA55C},
      );
      final json = original.toJson();
      expect(json['cl'], 1.25);
      expect(json['cb'], 'iron');
      expect(json['cc'], true);
      expect(json['pc'], {'20.412': 0xFFD9473B, '1.25': 0xFF3BA55C});

      final back = GymPlace.fromJson(json);
      expect(back.collarKg, 1.25);
      expect(back.colourBase, PlateColourBase.iron);
      expect(back.customColours, isTrue);
      expect(back.plateColours, {20.412: 0xFFD9473B, 1.25: 0xFF3BA55C});
      expect(back.plates, {20.0: 2});
      expect(back.bar, 15);
    });

    test('copyWith keeps the new fields it is not asked to change', () {
      final p = GymPlace(
        id: 'a',
        name: 'Home',
        equipment: {},
        collarKg: 2,
        colourBase: PlateColourBase.iron,
        customColours: true,
        plateColours: {20.0: 1},
      );
      final q = p.copyWith(name: 'Gym');
      expect(q.collarKg, 2);
      expect(q.colourBase, PlateColourBase.iron);
      expect(q.customColours, isTrue);
      expect(q.plateColours, {20.0: 1});
    });

    test('clearing the stock leaves collars and colours alone', () {
      final id = _id();
      fit.setPlaceCollar(id, 1);
      fit.setPlateColour(id, 20, const Color(0xFFD9473B));
      fit.setPlatePairs(id, 20, 2);
      fit.clearPlates(id);
      final p = fit.places.single;
      expect(p.plates, isEmpty);
      expect(p.collarKg, 1);
      expect(p.customColours, isTrue);
      expect(p.plateColours, isNotEmpty);
    });
  });
}
