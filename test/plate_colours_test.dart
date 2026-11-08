import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gymmane/services/local_store.dart';
import 'package:gymmane/state/fit_state.dart';
import 'package:gymmane/theme/plate_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _brass = Color(0xFFA67C52);

String _id() {
  final id = fit.addPlace('Home', equipment: {'Barbell'});
  fit.setActivePlace(id);
  return id;
}

void _reset() {
  fit.setUnits('kg');
  fit.places.clear();
  fit.activePlaceId = '';
  fit.plateBar = null;
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

    test('a 1.25 kg plate is chrome with no gym picked', () {
      expect(fit.plateColourFor(1.25, _brass), const Color(0xFFC8CCD0));
    });

    test('the 0.05 kg tolerance holds at its floating point edge', () {
      expect(c(1.3), const Color(0xFFC8CCD0));
      expect(c(1.2), const Color(0xFFC8CCD0));
      expect(c(1.31), const Color(0xFF777777));
      final over = {20.0: 0xFF123456};
      expect(c(20.05, custom: true, over: over), const Color(0xFF123456));
      expect(c(20.06, custom: true, over: over), const Color(0xFF777777));
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
}
