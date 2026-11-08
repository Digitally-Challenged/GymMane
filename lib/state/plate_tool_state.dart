part of 'fit_state.dart';

/// The plate calculator's state and maths: the target and bar of the Load tab, the plate counts of
/// the What's on it? tab, and how a weight splits into plates for the active gym. Weights stored
/// in kg, shown in the display unit. [ToolsState] builds on it for the 1RM percentage.
mixin PlateToolState on FitCore {
  double plateTarget = 100;
  double? plateBar;
  final Map<double, int> reverseCounts = {};

  List<double> get barOptions => isLb ? const [45, 35, 15] : const [20, 15, 10];

  List<double> get plateSizes => _plateSteps;

  List<double> get _plateSteps =>
      isLb ? const [45, 35, 25, 10, 5, 2.5] : const [25, 20, 15, 10, 5, 2.5, 1.25];

  List<double> get plateBarOptions {
    final bars = [...barOptions];
    final gym = defaultBar;
    if (!bars.any((b) => (b - gym).abs() < 0.05)) bars.add(gym);
    return bars..sort((a, b) => b.compareTo(a));
  }

  double get collarsDisplay => _round1(2 * toDisplayWeight(placeCollarKg));

  double collarsFor(String id, {String equipment = 'Barbell'}) =>
      equipment == 'Barbell' && !hasOwnBar(id) ? collarsDisplay : 0;

  /// The target as shown on screen (0.1 of a pound or kilo). The plates are worked out from this,
  /// not from the kilos kept to 0.01: 315 lb is stored as 142.88 kg, which is 314.996 lb, and
  /// the fill then swaps the third 45 for a 35 and a 10.
  double get plateTargetDisplay => _round1(toDisplayWeight(plateTarget));

  List<PlateCount> get plateBreakdown =>
      platesPerSide(plateTargetDisplay, plateBarDisplay, collars: collarsDisplay);

  double get defaultBar {
    final placeBar = placeBarKg;
    if (placeBar != null) return _round1(toDisplayWeight(placeBar));
    return isLb ? 45 : 20;
  }

  Map<double, int>? get plateStockDisplay {
    final stock = plateStockKg;
    if (stock == null) return null;
    return {for (final e in stock.entries) _round2(toDisplayWeight(e.key)): e.value};
  }

  List<PlateCount> platesPerSide(double displayTarget, double displayBar, {double collars = 0}) {
    final stock = plateStockDisplay;
    final steps = stock == null
        ? _plateSteps
        : (stock.keys.toList()..sort((a, b) => b.compareTo(a)));
    double perSide = math.max(0, (displayTarget - displayBar - collars) / 2);
    final out = <PlateCount>[];
    for (final p in steps) {
      var count = (perSide / p + 1e-6).floor();
      if (stock != null) count = math.min(count, stock[p] ?? 0);
      if (count > 0) {
        out.add((weight: p, count: count));
        perSide = _round1(perSide - count * p);
      }
    }
    return out;
  }

  double loadableTotal(double displayTarget, double displayBar, {double collars = 0}) {
    final parts = platesPerSide(displayTarget, displayBar, collars: collars);
    return _round1(displayBar + collars + parts.fold<double>(0, (a, p) => a + p.weight * p.count) * 2);
  }

  bool hasOwnBar(String id) => exerciseBar.containsKey(id);

  double barFor(String id, {String equipment = 'Barbell'}) {
    final kg = exerciseBar[id];
    if (kg != null) return _round1(toDisplayWeight(kg));
    return equipment == 'Barbell' ? defaultBar : 0;
  }

  void setExerciseBar(String id, double? displayKg) {
    if (displayKg == null) {
      exerciseBar.remove(id);
    } else {
      exerciseBar[id] = fromDisplayWeight(displayKg.clamp(0, isLb ? 1100 : 500).toDouble());
    }
    _persist();
    notifyListeners();
  }

  String? plateHint(String equipment, double weightKg, {String id = ''}) {
    if (equipment != 'Barbell' && !hasOwnBar(id)) return null;
    final bar = barFor(id, equipment: equipment);
    final target = _round1(toDisplayWeight(weightKg));
    if (target <= bar) return null;
    final parts = platesPerSide(target, bar, collars: collarsFor(id, equipment: equipment));
    if (parts.isEmpty) return null;
    return parts
        .map((p) => p.count == 1 ? fmt(p.weight) : '${fmt(p.weight)}×${p.count}')
        .join(' · ');
  }

  void bumpPlateTarget(double d) { plateTarget = _clamp(plateTarget + d, 0, null); notifyListeners(); }

  /// One [plateStep] up ([direction] 1) or down (-1) from the target as shown, landing on the plate
  /// grid (220.5 lb goes to 225 up and 220 down; never below 0). Stepping in kilos instead would
  /// add 5.0045 lb a tap, and 275 lb would read 330.1 after eleven.
  void stepPlateTarget(int direction) {
    final step = plateStep;
    final shown = plateTargetDisplay;
    final next = direction > 0
        ? (shown / step + 1e-6).floor() * step + step
        : math.max(0.0, (shown / step - 1e-6).ceil() * step - step);
    plateTarget = _clamp(fromDisplayWeight(next), 0, null);
    notifyListeners();
  }

  void setPlateBar(double b) { plateBar = fromDisplayWeight(b); notifyListeners(); }

  double get plateBarDisplay => plateBar == null ? defaultBar : _round1(toDisplayWeight(plateBar!));

  void bumpReverse(double size, int d) {
    final next = math.max(0, (reverseCounts[size] ?? 0) + d);
    next == 0 ? reverseCounts.remove(size) : reverseCounts[size] = next;
    notifyListeners();
  }

  void clearReverse() {
    reverseCounts.clear();
    notifyListeners();
  }

  double get reverseTotal {
    final perSide = reverseCounts.entries.fold<double>(0, (a, e) => a + e.key * e.value);
    return _round1(plateBarDisplay + collarsDisplay + 2 * perSide);
  }

  /// The reverse counts and the picked bar are keyed by display size, so they clear. The target
  /// snaps to the new unit's [plateStep] grid: 247.5 kg would otherwise show as 545.6 lb, which no
  /// plates can load, until the first tap.
  @override
  void onUnitsChanged() {
    super.onUnitsChanged();
    reverseCounts.clear();
    plateBar = null;
    plateTarget = _clamp(fromDisplayWeight(_roundTo(plateTargetDisplay, plateStep)), 0, null);
  }
}
