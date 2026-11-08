import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/place.dart';
import '../../state/fit_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/plate_palette.dart';
import '../glass.dart';
import '../ui_kit.dart';
import 'plate_disc.dart';
import 'plate_tool_cards.dart' show plateLabelStyle;

const double _collarStepLb = 0.5;
const double _collarStepKg = 0.25;
const int _discColumns = 3;
const double _discGap = 8;
const double _gridMaxWidth = 400;
const double _swatchSize = 48;
const double _swatchGap = 14;
const int _swatchColumns = 4;
const double _hitSize = 44;
const double _defaultBarLb = 45;
const double _defaultBarKg = 20;

/// Opens the "Plates and bar" editor for [place]: the bar, the collars, the plate colours and a
/// disc per plate size counting the pairs the gym owns. The sheet re-reads the gym by id from
/// `fit.places` on every change, so [place] itself may be stale.
void showPlateInventory(BuildContext context, GymPlace place) {
  showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => ListenableBuilder(
      listenable: fit,
      builder: (sheet, _) =>
          _InventorySheet(place: fit.places.firstWhere((p) => p.id == place.id, orElse: () => place)),
    ),
  );
}

BoxDecoration _sheetDecoration(GymColors gc) => BoxDecoration(
  color: gc.bgRaised,
  border: Border.all(color: gc.border),
  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
);

TextStyle _titleStyle(GymColors gc) =>
    AppTheme.d(14, weight: FontWeight.w700, color: gc.text, letterSpacing: 2);

double _round1(double n) => (n * 10).round() / 10;

class _InventorySheet extends StatelessWidget {
  const _InventorySheet({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Container(
      padding: sheetPad(context),
      decoration: _sheetDecoration(gc),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 18),
            Text(t.placePlates, textAlign: TextAlign.center, style: _titleStyle(gc)),
            const SizedBox(height: 4),
            Text(
              place.name,
              textAlign: TextAlign.center,
              style: AppTheme.s(12.5, color: gc.textSecondary),
            ),
            const SizedBox(height: 20),
            _BarRow(place: place),
            const SizedBox(height: 8),
            _CollarsRow(place: place),
            const SizedBox(height: 18),
            _ColoursSection(place: place),
            const SizedBox(height: 18),
            _PairsHeader(place: place),
            _DiscGrid(place: place),
            const SizedBox(height: 14),
            Text(
              t.plateColourHint,
              textAlign: TextAlign.center,
              style: AppTheme.s(12, color: gc.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 14),
            PrimaryButton(label: t.done, onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

/// The bar weight. A gym with no bar of its own shows the standard one.
class _BarRow extends StatelessWidget {
  const _BarRow({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final bar = place.bar == null
        ? (fit.isLb ? _defaultBarLb : _defaultBarKg)
        : _round1(fit.toDisplayWeight(place.bar!));
    return ToolRow(
      label: t.barWeight,
      control: StepperControl(
        value: '${fmt(bar)} ${fit.units}',
        minWidth: 66,
        btnSize: 28,
        gap: 8,
        fontSize: 14,
        onDec: () => fit.setPlaceBar(place.id, fit.fromDisplayWeight(bar - fit.plateStep)),
        onInc: () => fit.setPlaceBar(place.id, fit.fromDisplayWeight(bar + fit.plateStep)),
      ),
    );
  }
}

/// The weight of one collar, stepped in half pounds or quarter kilos as shown and stored in kg.
class _CollarsRow extends StatelessWidget {
  const _CollarsRow({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final step = fit.isLb ? _collarStepLb : _collarStepKg;
    // Snap to the step so the 0.001 kg rounding of the stored value never creeps into the label.
    final shown = (fit.toDisplayWeight(place.collarKg) / step).round() * step;
    void move(double to) => fit.setPlaceCollar(place.id, fit.fromDisplayWeight(to));
    return ToolRow(
      label: t.plateCollars,
      control: StepperControl(
        value: '${fmt(shown)} ${fit.units}',
        minWidth: 66,
        btnSize: 28,
        gap: 8,
        fontSize: 14,
        onDec: () => move(shown - step),
        onInc: () => move(shown + step),
      ),
    );
  }
}

/// Coloured / Iron / Custom. Custom is there to come back to: it stays muted until a plate has
/// been given a colour of its own.
class _ColoursSection extends StatelessWidget {
  const _ColoursSection({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    bool preset(PlateColourBase base) => !place.customColours && place.colourBase == base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.plateColours, style: plateLabelStyle(gc)),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegToggle([
            SegOption(
              t.plateColoursColoured,
              preset(PlateColourBase.coloured),
              () => fit.setPlaceColourBase(place.id, PlateColourBase.coloured),
            ),
            SegOption(
              t.plateColoursIron,
              preset(PlateColourBase.iron),
              () => fit.setPlaceColourBase(place.id, PlateColourBase.iron),
            ),
            SegOption(
              t.plateColoursCustom,
              place.customColours,
              () => fit.setPlaceCustom(place.id),
              enabled: place.plateColours.isNotEmpty,
            ),
          ]),
        ),
      ],
    );
  }
}

/// The PAIRS label, and "Everything available" when there is a stock to clear. Clearing leaves
/// the collars and colours alone.
class _PairsHeader extends StatelessWidget {
  const _PairsHeader({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _hitSize),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(t.platePairs, style: plateLabelStyle(gc)),
          if (place.plates.isNotEmpty)
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => fit.clearPlates(place.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _hitSize),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Text(
                      t.platesAll,
                      textAlign: TextAlign.right,
                      style: AppTheme.s(12, weight: FontWeight.w600, color: gc.accent),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One disc per plate size, three to a row. An empty stock means everything is available, so
/// every disc shows ∞; once there is a stock, a size with no pairs is dimmed.
class _DiscGrid extends StatelessWidget {
  const _DiscGrid({required this.place});

  final GymPlace place;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _gridMaxWidth),
        child: GridView.count(
          crossAxisCount: _discColumns,
          mainAxisSpacing: _discGap,
          crossAxisSpacing: _discGap,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [for (final size in fit.plateSizes) _disc(context, gc, size)],
        ),
      ),
    );
  }

  Widget _disc(BuildContext context, GymColors gc, double size) {
    final kg = fit.fromDisplayWeight(size);
    final stocked = place.plates.isNotEmpty;
    final pairs = fit.platePairs(place, kg);
    final colour = fit.plateColourFor(size, gc.brass, place: place);
    return PlateDisc(
      size: size,
      colour: colour,
      count: stocked ? pairs : null,
      dimmed: stocked && pairs == 0,
      onDec: stocked && pairs > 0 ? () => fit.setPlatePairs(place.id, kg, pairs - 1) : null,
      onInc: () => fit.setPlatePairs(place.id, kg, pairs + 1),
      onLongPress: () => _pickColour(context, place.id, size, colour),
    );
  }
}

Future<void> _pickColour(BuildContext context, String placeId, double size, Color current) =>
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _SwatchSheet(placeId: placeId, size: size, current: current),
    );

/// The fixed set of colours for one plate. Picking one stores it for the gym, turns Custom on
/// and closes the sheet.
class _SwatchSheet extends StatelessWidget {
  const _SwatchSheet({required this.placeId, required this.size, required this.current});

  final String placeId;
  final double size;
  final Color current;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Container(
      padding: sheetPad(context),
      decoration: _sheetDecoration(gc),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 18),
          Text(
            t.plateColourOf('${fmt(size)} ${fit.units}'),
            textAlign: TextAlign.center,
            style: _titleStyle(gc),
          ),
          const SizedBox(height: 20),
          _SwatchGrid(
            current: current,
            onPick: (c) {
              fit.setPlateColour(placeId, fit.fromDisplayWeight(size), c);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

/// The swatches in rows of [_swatchColumns], so the eight fall as two even rows on any phone
/// instead of wrapping six and two.
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({required this.current, required this.onPick});

  final Color current;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < kPlateSwatches.length; i += _swatchColumns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _swatchGap));
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (j, c) in kPlateSwatches.skip(i).take(_swatchColumns).indexed) ...[
              if (j > 0) const SizedBox(width: _swatchGap),
              _Swatch(colour: c, selected: c.toARGB32() == current.toARGB32(), onTap: () => onPick(c)),
            ],
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// A round colour with a ring when it is the plate's current one.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.selected, required this.onTap});

  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Semantics(
      key: ValueKey('plate-swatch-${colour.toARGB32()}'),
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: _swatchSize,
          height: _swatchSize,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? gc.text : Colors.transparent, width: 2),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour,
              border: plateNeedsOutline(colour) ? Border.all(color: gc.border) : null,
            ),
          ),
        ),
      ),
    );
  }
}
