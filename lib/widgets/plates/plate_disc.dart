import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../state/fit_state.dart' show fmt;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/plate_palette.dart';

const double _hitSize = 44;
const double _unboundedDiameter = 96;

// Plates are dark or light whatever the app theme, so these two do not come from GymColors.
const Color _darkInk = Color(0xFF1A1713);
const Color _lightInk = Color(0xFFFFFFFF);

/// A plate seen face-on: the size on top, a dark hub with how many there are
/// ([count] null means unlimited stock and shows ∞), and − / + at the lower
/// left and right.
///
/// The disc fills the smaller side of the space it is given. Each button is a
/// 44 × 44 hit area inside the disc; a null callback greys that button out.
/// [onLongPress] fires on the plate itself, not on the buttons.
class PlateDisc extends StatelessWidget {
  const PlateDisc({
    super.key,
    required this.size,
    required this.colour,
    required this.count,
    required this.onDec,
    required this.onInc,
    this.onLongPress,
    this.dimmed = false,
  });

  final double size;
  final Color colour;
  final int? count;
  final VoidCallback? onDec;
  final VoidCallback? onInc;
  final VoidCallback? onLongPress;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return LayoutBuilder(
      builder: (context, box) {
        final d = _diameter(box);
        final ink = _inkOn(colour);
        return Opacity(
          opacity: dimmed ? 0.35 : 1,
          child: SizedBox.square(
            dimension: d,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(onLongPress: onLongPress, child: _face(gc, d, ink)),
                ),
                ..._buttons(d, ink),
              ],
            ),
          ),
        );
      },
    );
  }

  double _diameter(BoxConstraints box) {
    final d = [
      box.maxWidth,
      box.maxHeight,
    ].where((v) => v.isFinite).fold<double?>(null, (m, v) => m == null || v < m ? v : m);
    return d ?? _unboundedDiameter;
  }

  Widget _face(GymColors gc, double d, Color ink) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour,
        border: plateNeedsOutline(colour) ? Border.all(color: gc.border) : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _Rim(inset: d * 0.06, colour: ink.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: d * 0.14,
            child: Center(
              child: Text(
                fmt(size),
                style: AppTheme.f(d * 0.2, weight: FontWeight.w800, color: ink),
              ),
            ),
          ),
          Positioned(
            left: d * 0.34,
            top: d * 0.36,
            width: d * 0.32,
            height: d * 0.32,
            child: _Hub(count: count, diameter: d * 0.32),
          ),
        ],
      ),
    );
  }

  /// The − and + hit areas, centred a quarter of the way in from each side and
  /// floored so a whole 44 × 44 box always stays inside the disc.
  List<Widget> _buttons(double d, Color ink) {
    final inset = math.max(d * 0.25, _hitSize / 2);
    Widget at(double centreX, Widget button) =>
        Positioned(left: centreX - _hitSize / 2, top: d - inset - _hitSize / 2, child: button);
    return [
      at(
        inset,
        _DiscButton(
          key: const ValueKey('plate-disc-dec'),
          glyph: '−',
          glyphSize: d * 0.24,
          label: '${t.decrease} ${fmt(size)}',
          ink: ink,
          onTap: onDec,
        ),
      ),
      at(
        d - inset,
        _DiscButton(
          key: const ValueKey('plate-disc-inc'),
          glyph: '+',
          glyphSize: d * 0.24,
          label: '${t.increase} ${fmt(size)}',
          ink: ink,
          onTap: onInc,
        ),
      ),
    ];
  }
}

/// The faint ring just inside the edge that makes the disc read as a plate.
class _Rim extends StatelessWidget {
  const _Rim({required this.inset, required this.colour});

  final double inset;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(inset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colour),
        ),
      ),
    );
  }
}

/// The dark centre showing how many of this plate there are, or ∞ for unlimited.
class _Hub extends StatelessWidget {
  const _Hub({required this.count, required this.diameter});

  final int? count;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle, color: _darkInk),
      child: Padding(
        padding: EdgeInsets.all(diameter * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            count?.toString() ?? '∞',
            style: AppTheme.f(diameter * 0.5, weight: FontWeight.w800, color: _lightInk),
          ),
        ),
      ),
    );
  }
}

/// One − or + : a 44 × 44 hit area with a screen-reader [label]. A null [onTap]
/// greys the glyph out and leaves the button inert.
class _DiscButton extends StatelessWidget {
  const _DiscButton({
    super.key,
    required this.glyph,
    required this.glyphSize,
    required this.label,
    required this.ink,
    required this.onTap,
  });

  final String glyph;
  final double glyphSize;
  final String label;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: _hitSize,
          child: Center(
            child: Text(
              glyph,
              style: AppTheme.f(
                glyphSize,
                weight: FontWeight.w600,
                color: onTap == null ? ink.withValues(alpha: 0.35) : ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whichever of the two inks reads better on [plate]: the one with the higher
/// WCAG contrast ratio, so yellow and green plates get dark ink as well as white ones.
Color _inkOn(Color plate) => _contrast(_darkInk, plate) > _contrast(_lightInk, plate) ? _darkInk : _lightInk;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
