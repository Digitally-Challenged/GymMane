import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/plate_math.dart';
import '../../state/fit_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../ui_kit.dart';
import 'plate_chips.dart';
import 'plate_disc.dart';

const double _stepSize = 52;
const double _hitSize = 44;
const double _discGap = 8;
const int _discColumns = 3;

// Like the screen that holds them, these read the global `fit` and are rebuilt by the app.
// Create them without `const`, or a const instance is skipped and shows stale numbers.

/// The colour the active gym gives a plate of [size].
Color Function(double size) plateColourOf(GymColors gc) =>
    (size) => fit.plateColourFor(size, gc.brass);

TextStyle _labelStyle(GymColors gc) =>
    AppTheme.f(10.5, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 1.4);

/// The bar drawing with the big total under it. Passing [onDec] and [onInc] adds a − and a +
/// either side of the total; passing [onEdit] makes tapping the total type a number.
class PlateTotalCard extends StatelessWidget {
  const PlateTotalCard({
    super.key,
    required this.barbell,
    required this.total,
    required this.otherUnit,
    this.onEdit,
    this.onDec,
    this.onInc,
  });

  final Widget barbell;
  final String total;
  final String otherUnit;
  final VoidCallback? onEdit;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(color: gc.bgRaised, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          barbell,
          const SizedBox(height: 14),
          Row(
            children: [
              if (onDec != null)
                _StepButton(
                  key: const ValueKey('plate-step-dec'),
                  glyph: '−',
                  label: t.decrease,
                  onTap: onDec!,
                ),
              Expanded(
                child: _Readout(total: total, otherUnit: otherUnit, onEdit: onEdit),
              ),
              if (onInc != null)
                _StepButton(
                  key: const ValueKey('plate-step-inc'),
                  glyph: '+',
                  label: t.increase,
                  onTap: onInc!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.total, required this.otherUnit, required this.onEdit});

  final String total;
  final String otherUnit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Semantics(
      button: onEdit != null,
      child: GestureDetector(
        key: const ValueKey('plate-total'),
        behavior: HitTestBehavior.opaque,
        onTap: onEdit,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    total,
                    style: AppTheme.f(44, weight: FontWeight.w800, color: gc.text),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fit.units,
                    style: AppTheme.f(18, weight: FontWeight.w700, color: gc.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              otherUnit,
              style: AppTheme.f(14, weight: FontWeight.w600, color: gc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round − or + drawn as text, like the glyphs on a plate disc.
class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.glyph, required this.label, required this.onTap});

  final String glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: Container(
          width: _stepSize,
          height: _stepSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: gc.bgRaised2, shape: BoxShape.circle),
          child: Text(
            glyph,
            style: AppTheme.f(28, weight: FontWeight.w500, color: gc.text, height: 1),
          ),
        ),
      ),
    );
  }
}

/// The bar the plates go on, shared by both tabs. [trailing] sits at the right of the label.
class PlateBarChoice extends StatelessWidget {
  const PlateBarChoice({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return SoftCard(
      radius: 20,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.barWeight, style: _labelStyle(gc))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final bar in fit.plateBarOptions) _barOption(gc, bar)],
          ),
        ],
      ),
    );
  }

  Widget _barOption(GymColors gc, double bar) {
    final active = (fit.plateBarDisplay - bar).abs() < 0.05;
    return Pressable(
      onTap: () => fit.setPlateBar(bar),
      scale: 0.95,
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? gc.ember : gc.bgRaised2,
          borderRadius: BorderRadius.circular(10),
        ),
        // widthFactor and heightFactor keep the option as wide as its label; alignment on the
        // Container would stretch it across the whole Wrap line.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            '${fmt(bar)} ${fit.units}',
            style: AppTheme.f(13, weight: FontWeight.w600, color: active ? gc.onEmber : gc.textSecondary),
          ),
        ),
      ),
    );
  }
}

class PlateClearButton extends StatelessWidget {
  const PlateClearButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _hitSize, minHeight: _hitSize),
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              t.plateClear,
              style: AppTheme.f(
                13,
                weight: FontWeight.w700,
                color: onTap == null ? gc.textTertiary : gc.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One side of the bar as chips and the sum, or "Just the bar.", plus the warning in brass when
/// the stock cannot reach the target.
class PlatePerSideCard extends StatelessWidget {
  const PlatePerSideCard({
    super.key,
    required this.plates,
    required this.bar,
    required this.collars,
    required this.loadable,
    required this.reachesTarget,
  });

  final List<PlateCount> plates;
  final double bar;
  final double collars;
  final double loadable;
  final bool reachesTarget;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return SoftCard(
      radius: 20,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.perSide, style: _labelStyle(gc)),
          const SizedBox(height: 10),
          if (plates.isEmpty)
            Text(
              t.justTheBar,
              style: AppTheme.f(13, weight: FontWeight.w500, color: gc.textSecondary),
            )
          else ...[
            PlateChips(perSide: plates, colourOf: plateColourOf(gc)),
            const SizedBox(height: 10),
            Text(
              plateSumLine(bar: bar, collars: collars, perSide: plates, total: loadable),
              style: AppTheme.f(13, weight: FontWeight.w500, color: gc.textSecondary),
            ),
          ],
          if (!reachesTarget) ...[
            const SizedBox(height: 8),
            Text(
              t.plateAchievable('${fmt(loadable)} ${fit.units}'),
              style: AppTheme.f(12, weight: FontWeight.w500, color: gc.brass),
            ),
          ],
        ],
      ),
    );
  }
}

/// One disc per plate size, three to a row, each counting the plates on one side.
class PlateDiscGrid extends StatelessWidget {
  const PlateDiscGrid({super.key, required this.colourOf});

  final Color Function(double size) colourOf;

  @override
  Widget build(BuildContext context) {
    final sizes = fit.plateSizes;
    return Column(
      children: [
        for (var i = 0; i < sizes.length; i += _discColumns) ...[
          if (i > 0) const SizedBox(height: _discGap),
          Row(
            children: [
              for (var j = i; j < i + _discColumns; j++) ...[
                if (j > i) const SizedBox(width: _discGap),
                Expanded(
                  child: j < sizes.length
                      ? AspectRatio(aspectRatio: 1, child: _disc(sizes[j]))
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _disc(double size) {
    final count = fit.reverseCounts[size] ?? 0;
    return PlateDisc(
      size: size,
      colour: colourOf(size),
      count: count,
      onDec: count > 0 ? () => fit.bumpReverse(size, -1) : null,
      onInc: () => fit.bumpReverse(size, 1),
    );
  }
}
