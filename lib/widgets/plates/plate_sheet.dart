import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/plate_math.dart';
import '../../state/fit_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../glass.dart';
import '../ui_kit.dart';
import 'barbell_view.dart';
import 'plate_chips.dart';
import 'plate_tool_cards.dart' show plateColourOf, plateLabelStyle;

const double _barbellHeight = 100;
const double _optionGap = 8;
const double _barTolerance = 0.05;

/// The sheet behind a plate hint: the drawn bar, [displayTarget] in the display unit, the plates
/// for one side and, when [previousDisplay] is given, what to add or take off since the previous
/// set. The bar starts at [startBar] (the gym's bar when null) and can be switched in place;
/// [collars] is the combined weight of both collars, 0 for none.
///
/// Both weights are rounded to 0.1 first, like the plate tool does: a weight stored in kilos
/// comes back from [FitCore.toDisplayWeight] a hair off (315 lb as 314.996), and the fill would
/// then trade a 45 for a 35 and a 10.
void showPlateSheet(
  BuildContext context,
  double displayTarget, {
  double? startBar,
  double collars = 0,
  double? previousDisplay,
}) {
  showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PlateSheet(
      target: _tenth(displayTarget),
      startBar: startBar ?? fit.defaultBar,
      collars: collars,
      previous: previousDisplay == null ? null : _tenth(previousDisplay),
    ),
  );
}

double _tenth(double n) => (n * 10).round() / 10;

class _PlateSheet extends StatefulWidget {
  const _PlateSheet({
    required this.target,
    required this.startBar,
    required this.collars,
    required this.previous,
  });

  final double target;
  final double startBar;
  final double collars;
  final double? previous;

  @override
  State<_PlateSheet> createState() => _PlateSheetState();
}

class _PlateSheetState extends State<_PlateSheet> {
  late double _bar = widget.startBar;
  late final List<double> _bars = _barChoices();

  /// The usual bars, heaviest first, plus the one the sheet started on when it is not among them.
  List<double> _barChoices() {
    final bars = [...fit.plateBarOptions];
    if (!bars.any((b) => (b - widget.startBar).abs() < _barTolerance)) bars.add(widget.startBar);
    return bars..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final plates = fit.platesPerSide(widget.target, _bar, collars: widget.collars);
    final loadable = fit.loadableTotal(widget.target, _bar, collars: widget.collars);
    final change = _changeText(plates);
    return Container(
      padding: sheetPad(context),
      decoration: BoxDecoration(
        color: gc.bgRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // Everything fits a 667 pt phone; the scroll view only catches a landscape or tiny screen.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 14),
            BarbellView(
              perSide: plates,
              colourOf: plateColourOf(gc),
              largest: fit.plateSizes.first,
              height: _barbellHeight,
              collar: widget.collars > 0,
            ),
            const SizedBox(height: 6),
            _Target(target: widget.target),
            const SizedBox(height: 10),
            _Loadout(plates: plates, colourOf: plateColourOf(gc)),
            if (change != null) ...[const SizedBox(height: 12), _ChangeLine(text: change)],
            if (loadable < widget.target - 0.01) ...[
              const SizedBox(height: 8),
              Text(
                t.plateAchievable('${fmt(loadable)} ${fit.units}'),
                textAlign: TextAlign.center,
                style: AppTheme.f(12, weight: FontWeight.w500, color: gc.brass),
              ),
            ],
            const SizedBox(height: 14),
            _BarPicker(bars: _bars, selected: _bar, onPick: (bar) => setState(() => _bar = bar)),
            const SizedBox(height: 14),
            PrimaryButton(label: t.done, onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  /// What changes on each side since the previous set, on the bar picked now; null when there is
  /// no previous set or it loads the same plates.
  String? _changeText(List<PlateCount> plates) {
    final previous = widget.previous;
    if (previous == null) return null;
    final before = fit.platesPerSide(previous, _bar, collars: widget.collars);
    final change = plateChange(before, plates);
    return switch ((change.off.isEmpty, change.on.isEmpty)) {
      (true, true) => null,
      (true, false) => t.plateChangeAdd(plateList(change.on)),
      (false, true) => t.plateChangeOff(plateList(change.off)),
      (false, false) => t.plateChangeSwap(plateList(change.off), plateList(change.on)),
    };
  }
}

class _Target extends StatelessWidget {
  const _Target({required this.target});

  final double target;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            fmt(target),
            style: AppTheme.f(36, weight: FontWeight.w800, color: gc.text),
          ),
          const SizedBox(width: 6),
          Text(
            fit.units,
            style: AppTheme.f(16, weight: FontWeight.w700, color: gc.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The plates for one side as chips, or "Just the bar.".
class _Loadout extends StatelessWidget {
  const _Loadout({required this.plates, required this.colourOf});

  final List<PlateCount> plates;
  final Color Function(double size) colourOf;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Column(
      children: [
        Text(t.perSide, style: plateLabelStyle(gc)),
        const SizedBox(height: 8),
        if (plates.isEmpty)
          Text(
            t.justTheBar,
            style: AppTheme.f(14, weight: FontWeight.w500, color: gc.textSecondary),
          )
        else
          PlateChips(perSide: plates, colourOf: colourOf),
      ],
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return DecoratedBox(
      decoration: BoxDecoration(color: gc.accentSoft, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTheme.f(15, weight: FontWeight.w700, color: gc.accent),
        ),
      ),
    );
  }
}

/// One row of bars to pick from; the sheet works the plates out for the one that is on.
class _BarPicker extends StatelessWidget {
  const _BarPicker({required this.bars, required this.selected, required this.onPick});

  final List<double> bars;
  final double selected;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Column(
      children: [
        Text(t.barWeight, style: plateLabelStyle(gc)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final bar in bars) ...[
              if (bar != bars.first) const SizedBox(width: _optionGap),
              Expanded(child: _option(gc, bar)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _option(GymColors gc, double bar) {
    final active = (selected - bar).abs() < _barTolerance;
    return Semantics(
      button: true,
      selected: active,
      child: Pressable(
        onTap: () => onPick(bar),
        scale: 0.95,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? gc.ember : gc.bgRaised2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${fmt(bar)} ${fit.units}',
              style: AppTheme.f(13, weight: FontWeight.w600, color: active ? gc.onEmber : gc.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
