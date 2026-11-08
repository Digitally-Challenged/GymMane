import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/plate_math.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/plates/barbell_view.dart';
import '../widgets/plates/plate_tool_cards.dart';
import '../widgets/ui_kit.dart';

const double _cardGap = 10;

// These widgets read the global `fit`, and the app rebuilds the tool screen when `fit` changes.
// Create them without `const` (`_LoadTab()`): a const instance is identical to the last one,
// so Flutter would skip it and it would keep showing stale numbers. Same for the cards.

/// Tools → Plates below its header: a Load tab (target weight to plates) and a
/// What's on it? tab (plates to total weight). The app's `fit` listener rebuilds it
/// like the other tool screens.
class PlateToolBody extends StatelessWidget {
  const PlateToolBody({super.key});

  @override
  Widget build(BuildContext context) => _PlateTabs();
}

/// Holds which tab is open. Load is first, and the choice is forgotten on leaving the tool.
class _PlateTabs extends StatefulWidget {
  const _PlateTabs();

  @override
  State<_PlateTabs> createState() => _PlateTabsState();
}

class _PlateTabsState extends State<_PlateTabs> {
  bool _reverse = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SegToggle(
              [
                SegOption(t.plateTabLoad, !_reverse, () => setState(() => _reverse = false)),
                SegOption(t.plateTabReverse, _reverse, () => setState(() => _reverse = true)),
              ],
              hPad: 18,
              vPad: 9,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _reverse ? _ReverseTab() : _LoadTab(),
      ],
    );
  }
}

/// Target weight in, plates out.
class _LoadTab extends StatelessWidget {
  const _LoadTab();

  Future<void> _editTarget(BuildContext context) async {
    final typed = await askNumber(
      context,
      title: t.targetWeight,
      initial: fit.weightValue(fit.plateTarget),
      decimal: true,
    );
    if (typed != null) fit.bumpPlateTarget(fit.fromDisplayWeight(typed) - fit.plateTarget);
  }

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final target = fit.plateTargetDisplay;
    final collars = fit.collarsDisplay;
    final plates = fit.plateBreakdown;
    final loadable = fit.loadableTotal(target, fit.plateBarDisplay, collars: collars);
    final step = fit.fromDisplayWeight(fit.plateStep);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlateTotalCard(
          barbell: BarbellView(
            perSide: plates,
            colourOf: plateColourOf(gc),
            largest: fit.plateSizes.first,
            collar: collars > 0,
          ),
          total: fit.weightValue(fit.plateTarget),
          otherUnit: fit.otherUnitLabel(fit.plateTarget),
          onEdit: () => _editTarget(context),
          onDec: () => fit.bumpPlateTarget(-step),
          onInc: () => fit.bumpPlateTarget(step),
        ),
        const SizedBox(height: _cardGap),
        PlateBarChoice(),
        const SizedBox(height: _cardGap),
        PlatePerSideCard(
          plates: plates,
          bar: fit.plateBarDisplay,
          collars: collars,
          loadable: loadable,
          reachesTarget: loadable >= target - 0.01,
        ),
      ],
    );
  }
}

/// Plates in, total weight out.
class _ReverseTab extends StatelessWidget {
  const _ReverseTab();

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final counts = fit.reverseCounts;
    final plates = <PlateCount>[
      for (final size in fit.plateSizes)
        if ((counts[size] ?? 0) > 0) (weight: size, count: counts[size]!),
    ];
    final total = fit.reverseTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlateTotalCard(
          barbell: BarbellView(
            perSide: plates,
            colourOf: plateColourOf(gc),
            largest: fit.plateSizes.first,
            collar: fit.collarsDisplay > 0,
          ),
          total: fmt(total),
          otherUnit: fit.otherUnitLabel(fit.fromDisplayWeight(total)),
        ),
        const SizedBox(height: _cardGap),
        PlateBarChoice(trailing: PlateClearButton(onTap: counts.isEmpty ? null : fit.clearReverse)),
        const SizedBox(height: _cardGap),
        PlateDiscGrid(colourOf: plateColourOf(gc)),
      ],
    );
  }
}
