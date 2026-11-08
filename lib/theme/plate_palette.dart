import 'dart:ui' show Color;

/// Which preset a gym's plates start from. Custom colours sit on top of it.
enum PlateColourBase { coloured, iron }

const Color kPlateBlue = Color(0xFF2F6FD6);
const Color kPlateYellow = Color(0xFFE8C547);
const Color kPlateGreen = Color(0xFF3BA55C);
const Color kPlateWhite = Color(0xFFEEEEEE);
const Color kPlateRed = Color(0xFFD9473B);
const Color kPlateGrey = Color(0xFF777777);
const Color kPlateIron = Color(0xFF3A3A3A);
const Color kPlateChrome = Color(0xFFC8CCD0);
const Color kPlateBrassFixed = Color(0xFFB98F72);

/// The fixed row offered when a plate's colour is changed.
const List<Color> kPlateSwatches = [
  kPlateRed,
  kPlateBlue,
  kPlateYellow,
  kPlateGreen,
  kPlateWhite,
  kPlateIron,
  kPlateGrey,
  kPlateBrassFixed,
];

const double _lbPerKg = 2.20462;

const List<(double, Color)> _colouredLb = [
  (45, kPlateBlue),
  (35, kPlateYellow),
  (25, kPlateGreen),
  (10, kPlateWhite),
  (5, kPlateRed),
  (2.5, kPlateGrey),
];

const List<(double, Color)> _colouredKg = [
  (25, kPlateRed),
  (20, kPlateBlue),
  (15, kPlateYellow),
  (10, kPlateGreen),
  (5, kPlateWhite),
  (2.5, kPlateRed),
  (1.25, kPlateChrome),
];

const double _tolerance = 0.05;

Color? _near(List<(double, Color)> table, double size) {
  for (final (s, colour) in table) {
    if ((s - size).abs() < _tolerance) return colour;
  }
  return null;
}

/// The colour of one plate. [sizeKg] is the stored kg size; lb users resolve
/// it back to the display size (a 45 lb plate is stored as 20.412 kg).
/// A custom override within 0.05 kg wins while [custom] is on; otherwise the
/// [base] preset applies, and a size that is not a standard one is grey.
Color plateColour({
  required double sizeKg,
  required bool isLb,
  required PlateColourBase base,
  required bool custom,
  required Map<double, int> overridesKg,
  required Color brass,
}) {
  if (custom) {
    for (final e in overridesKg.entries) {
      if ((e.key - sizeKg).abs() < _tolerance) return Color(e.value);
    }
  }
  final size = isLb ? (sizeKg * _lbPerKg * 10).round() / 10 : sizeKg;
  final coloured = _near(isLb ? _colouredLb : _colouredKg, size);
  if (coloured == null) return kPlateGrey;
  if (base == PlateColourBase.coloured) return coloured;
  final largest = isLb ? 45.0 : 25.0;
  return (size - largest).abs() < _tolerance ? kPlateIron : brass;
}

/// Light plates need a thin outline to show on the light theme.
bool plateNeedsOutline(Color c) => c.computeLuminance() > 0.8;
