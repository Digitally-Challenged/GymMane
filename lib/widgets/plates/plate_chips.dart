import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/plate_math.dart';
import '../../state/fit_state.dart' show fmt;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/plate_palette.dart';

/// One chip per plate size for a single side of the bar: a colour swatch and
/// "45 ×2" (or just "25" when there is one). Chips wrap onto new lines.
class PlateChips extends StatelessWidget {
  const PlateChips({super.key, required this.perSide, required this.colourOf});

  final List<PlateCount> perSide;
  final Color Function(double size) colourOf;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final p in perSide) _chip(gc, p)]);
  }

  Widget _chip(GymColors gc, PlateCount plate) {
    final colour = colourOf(plate.weight);
    return DecoratedBox(
      decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 5,
              height: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                  border: plateNeedsOutline(colour) ? Border.all(color: gc.border) : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              plateList([plate]),
              style: AppTheme.f(15, weight: FontWeight.w700, color: gc.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// The working behind a loading, e.g. "45 bar + 2 × (45 + 45 + 25) = 275".
/// One term per plate; [collars] is the combined weight of both collars and
/// only appears when it is above zero.
String plateSumLine({
  required double bar,
  required double collars,
  required List<PlateCount> perSide,
  required double total,
}) {
  final plates = [
    for (final p in perSide)
      for (var i = 0; i < p.count; i++) fmt(p.weight),
  ].join(' + ');
  return collars > 0
      ? t.plateSumCollars(fmt(bar), fmt(collars), plates, fmt(total))
      : t.plateSum(fmt(bar), plates, fmt(total));
}
