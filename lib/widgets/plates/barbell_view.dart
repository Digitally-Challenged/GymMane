import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/plate_math.dart';
import '../../state/fit_state.dart' show fmt;
import '../../theme/app_colors.dart';
import '../../theme/plate_palette.dart';

const double _maxPlateWidth = 16;
const double _plateGap = 1;
const double _collarBlock = 12;
const double _sleeveInset = 4;
const double _tipInset = 6;
const double _unboundedWidth = 320;

/// One side of a barbell seen side-on: the shaft, the sleeve, an optional
/// collar block and the plates stacked from the inside out.
///
/// [perSide] lists the plates heaviest first, each size repeated [PlateCount.count]
/// times. A plate is [height] × (0.45 + 0.55 × size / [largest]) tall, never more
/// than [height]. Plates start 16 wide and shrink evenly so a heavy load still
/// fits on the sleeve. Light plates get a 1 px outline so they show on any theme.
class BarbellView extends StatelessWidget {
  const BarbellView({
    super.key,
    required this.perSide,
    required this.colourOf,
    required this.largest,
    this.height = 120,
    this.collar = true,
  });

  final List<PlateCount> perSide;
  final Color Function(double size) colourOf;
  final double largest;
  final double height;
  final bool collar;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite ? box.maxWidth : _unboundedWidth;
        return SizedBox(
          width: width,
          height: height,
          child: Stack(children: [..._steel(gc, width), ..._plates(gc, width)]),
        );
      },
    );
  }

  double get _collarSpace => collar ? _collarBlock : 0;

  /// Where the sleeve starts: after the shaft and the collar block.
  double _sleeveLeft(double width) => width * 0.14 + _collarSpace;

  List<Widget> _steel(GymColors gc, double width) {
    final sleeveLeft = _sleeveLeft(width);
    return [
      _rod(null, 0, sleeveLeft, height * 0.07, gc.textTertiary),
      _rod(const ValueKey('barbell-sleeve'), sleeveLeft, width - sleeveLeft, height * 0.11, gc.textSecondary),
      if (collar)
        Positioned(
          left: sleeveLeft - _collarBlock,
          top: height * 0.31,
          width: _collarBlock,
          height: height * 0.38,
          child: DecoratedBox(
            key: const ValueKey('barbell-collar'),
            decoration: BoxDecoration(
              color: gc.textSecondary,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: gc.border),
            ),
          ),
        ),
    ];
  }

  Widget _rod(Key? key, double left, double length, double thickness, Color colour) => Positioned(
    left: left,
    top: (height - thickness) / 2,
    width: length,
    height: thickness,
    child: DecoratedBox(
      key: key,
      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
    ),
  );

  List<Widget> _plates(GymColors gc, double width) {
    final total = perSide.fold<int>(0, (sum, p) => sum + p.count);
    if (total == 0) return const [];
    final left = _sleeveLeft(width) + _sleeveInset;
    final room = math.max(0.0, width - _tipInset - left);
    final plateWidth = math.min(_maxPlateWidth, math.max(0.0, (room - _plateGap * (total - 1)) / total));
    final out = <Widget>[];
    for (final p in perSide) {
      final plateHeight = _plateHeight(p.weight);
      final colour = colourOf(p.weight);
      for (var i = 0; i < p.count; i++) {
        final index = out.length;
        out.add(
          Positioned(
            left: left + index * (plateWidth + _plateGap),
            top: (height - plateHeight) / 2,
            width: plateWidth,
            height: plateHeight,
            child: DecoratedBox(
              key: ValueKey('plate-${fmt(p.weight)}-$index'),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(math.min(3, plateWidth / 2)),
                border: plateNeedsOutline(colour) ? Border.all(color: gc.border) : null,
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  double _plateHeight(double size) {
    final share = largest > 0 ? size / largest : 1.0;
    return (height * (0.45 + 0.55 * share)).clamp(0.0, height);
  }
}
