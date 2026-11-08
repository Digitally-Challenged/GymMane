import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/models/place.dart';
import 'package:gymmane/models/plate_math.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/plate_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _brass = Color(0xFFA67C52);

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

  group('colours', () {
    const red = Color(0xFFD9473B);

    test('custom colours sit on top of the preset', () {
      fit.setUnits('lb');
      final id = _id();
      fit.setPlaceColourBase(id, PlateColourBase.iron);
      expect(fit.plateColourFor(45, _brass), const Color(0xFF3A3A3A));
      expect(fit.plateColourFor(25, _brass), _brass);

      fit.setPlateColour(id, 20.412, red);
      expect(fit.places.single.customColours, isTrue);
      expect(fit.plateColourFor(45, _brass), red);
      expect(fit.plateColourFor(25, _brass), _brass, reason: 'only the 45 was overridden');

      fit.setPlaceColourBase(id, PlateColourBase.iron);
      expect(fit.places.single.customColours, isFalse);
      expect(fit.plateColourFor(45, _brass), const Color(0xFF3A3A3A));
      expect(fit.places.single.plateColours, {20.412: red.toARGB32()}, reason: 'overrides are kept');

      fit.setPlaceCustom(id);
      expect(fit.places.single.customColours, isTrue);
      expect(fit.plateColourFor(45, _brass), red);
    });

    test('switching to Coloured also leaves Custom and keeps the overrides', () {
      final id = _id();
      fit.setPlateColour(id, 20, red);
      fit.setPlaceColourBase(id, PlateColourBase.coloured);
      final p = fit.places.single;
      expect(p.colourBase, PlateColourBase.coloured);
      expect(p.customColours, isFalse);
      expect(p.plateColours, {20.0: red.toARGB32()});
      expect(fit.plateColourFor(20, _brass), const Color(0xFF2F6FD6));
    });

    test('lb stock and colour overrides resolve through kg keys', () {
      fit.setUnits('lb');
      final id = _id();
      fit.setPlatePairs(id, 20.412, 2);
      fit.setPlateColour(id, 20.412, red);
      final place = fit.places.single;

      expect(place.plates, {20.412: 2});
      expect(fit.platePairs(place, fit.fromDisplayWeight(45)), 2);
      expect(fit.plateColourFor(45, _brass), red);
      expect(fit.plateStockDisplay, {45.0: 2});
    });

    test('setting a colour on a size close to an existing key reuses the key', () {
      final id = _id();
      fit.setPlateColour(id, 20.412, red);
      fit.setPlateColour(id, 20.4117, const Color(0xFF3BA55C));
      expect(fit.places.single.plateColours.length, 1);
      expect(fit.places.single.plateColours.values.single, const Color(0xFF3BA55C).toARGB32());
    });

    test('no gym means the Coloured preset', () {
      expect(fit.plateColourFor(25, _brass), const Color(0xFFD9473B));
      expect(fit.plateColourFor(20, _brass), const Color(0xFF2F6FD6));
    });

    test('an explicit place wins over the active one', () {
      fit.setUnits('lb');
      final a = _id();
      fit.setPlaceColourBase(a, PlateColourBase.iron);
      final b = fit.addPlace('Other');
      final other = fit.places.firstWhere((p) => p.id == b);
      expect(fit.plateColourFor(45, _brass, place: other), const Color(0xFF2F6FD6));
      expect(fit.plateColourFor(45, _brass), const Color(0xFF3A3A3A));
    });
  });

  group('plateColour', () {
    Color c(double kg, {bool lb = false, PlateColourBase base = PlateColourBase.coloured, bool custom = false, Map<double, int> over = const {}}) =>
        plateColour(sizeKg: kg, isLb: lb, base: base, custom: custom, overridesKg: over, brass: _brass);

    test('coloured lb presets', () {
      final lb = {45.0: 0xFF2F6FD6, 35.0: 0xFFE8C547, 25.0: 0xFF3BA55C, 10.0: 0xFFEEEEEE, 5.0: 0xFFD9473B, 2.5: 0xFF777777};
      for (final e in lb.entries) {
        expect(c(e.key / 2.20462, lb: true), Color(e.value), reason: '${e.key} lb');
      }
    });

    test('coloured kg presets', () {
      final kg = {25.0: 0xFFD9473B, 20.0: 0xFF2F6FD6, 15.0: 0xFFE8C547, 10.0: 0xFF3BA55C, 5.0: 0xFFEEEEEE, 2.5: 0xFFD9473B, 1.25: 0xFFC8CCD0};
      for (final e in kg.entries) {
        expect(c(e.key), Color(e.value), reason: '${e.key} kg');
      }
    });

    test('iron keeps the biggest plate iron and the rest brass', () {
      expect(c(25, base: PlateColourBase.iron), const Color(0xFF3A3A3A));
      expect(c(20, base: PlateColourBase.iron), _brass);
      expect(c(1.25, base: PlateColourBase.iron), _brass);
      expect(c(45 / 2.20462, lb: true, base: PlateColourBase.iron), const Color(0xFF3A3A3A));
      expect(c(35 / 2.20462, lb: true, base: PlateColourBase.iron), _brass);
    });

    test('an override only counts while custom is on', () {
      final over = {20.0: 0xFF123456};
      expect(c(20, over: over), const Color(0xFF2F6FD6));
      expect(c(20, custom: true, over: over), const Color(0xFF123456));
      expect(c(20.04, custom: true, over: over), const Color(0xFF123456));
      expect(c(15, custom: true, over: over), const Color(0xFFE8C547));
    });

    test('an unknown size is grey', () {
      expect(c(3), const Color(0xFF777777));
      expect(c(3, base: PlateColourBase.iron), const Color(0xFF777777));
    });

    test('only light plates need an outline', () {
      expect(plateNeedsOutline(const Color(0xFFEEEEEE)), isTrue);
      for (final dark in [const Color(0xFF2F6FD6), const Color(0xFFE8C547), const Color(0xFFD9473B), const Color(0xFF3A3A3A)]) {
        expect(plateNeedsOutline(dark), isFalse);
      }
    });

    test('the swatch row is the eight fixed colours', () {
      expect(kPlateSwatches, [
        const Color(0xFFD9473B),
        const Color(0xFF2F6FD6),
        const Color(0xFFE8C547),
        const Color(0xFF3BA55C),
        const Color(0xFFEEEEEE),
        const Color(0xFF3A3A3A),
        const Color(0xFF777777),
        const Color(0xFFB98F72),
      ]);
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
