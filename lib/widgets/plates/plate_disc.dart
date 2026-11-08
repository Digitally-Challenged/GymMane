import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../state/fit_state.dart' show fmt;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/plate_palette.dart';

const double _hitSize = 44;
const double _unboundedDiameter = 96;
const Color _hub = Color(0xFF1A1713);

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
        final edge = d * 0.25 < _hitSize / 2 ? _hitSize / 2 : d * 0.25;
        return Opacity(
          opacity: dimmed ? 0.35 : 1,
          child: SizedBox.square(
            dimension: d,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(onLongPress: onLongPress, child: _face(gc, d, ink)),
                ),
                _button(d, edge, d - edge, '−', t.decrease, onDec, ink, 'plate-disc-dec'),
                _button(d, d - edge, d - edge, '+', t.increase, onInc, ink, 'plate-disc-inc'),
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
    final hub = d * 0.32;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour,
        border: plateNeedsOutline(colour) ? Border.all(color: gc.border) : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(d * 0.06),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ink.withValues(alpha: 0.18)),
                ),
              ),
            ),
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
            left: (d - hub) / 2,
            top: d * 0.36,
            width: hub,
            height: hub,
            child: DecoratedBox(
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _hub),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(hub * 0.12),
                  child: FittedBox(
                    child: Text(
                      count?.toString() ?? '∞',
                      style: AppTheme.f(hub * 0.5, weight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(
    double d,
    double cx,
    double cy,
    String glyph,
    String verb,
    VoidCallback? onTap,
    Color ink,
    String key,
  ) {
    return Positioned(
      left: cx - _hitSize / 2,
      top: cy - _hitSize / 2,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: '$verb ${fmt(size)}',
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey(key),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
            dimension: _hitSize,
            child: Center(
              child: Text(
                glyph,
                style: AppTheme.f(
                  d * 0.24,
                  weight: FontWeight.w600,
                  color: onTap == null ? ink.withValues(alpha: 0.35) : ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark ink on light plates, white on dark ones. The cut-off is where black and
/// white text have equal contrast, so a yellow plate gets dark ink too.
Color _inkOn(Color plate) => plate.computeLuminance() > 0.18 ? GymColors.light.text : Colors.white;
