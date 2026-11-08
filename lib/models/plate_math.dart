import '../state/fit_state.dart' show fmt;

/// One plate size and how many of it sit on a single side of the bar.
typedef PlateCount = ({double weight, int count});

/// The per-side difference between two loadings: what comes [off] and what
/// goes [on] to get from [from] to [to]. Both lists are heaviest first.
({List<PlateCount> off, List<PlateCount> on}) plateChange(
    List<PlateCount> from, List<PlateCount> to) {
  final before = _tally(from);
  final after = _tally(to);
  final off = <PlateCount>[];
  final on = <PlateCount>[];
  for (final w in {...before.keys, ...after.keys}) {
    final diff = (after[w] ?? 0) - (before[w] ?? 0);
    if (diff > 0) on.add((weight: w, count: diff));
    if (diff < 0) off.add((weight: w, count: -diff));
  }
  int heaviest(PlateCount a, PlateCount b) => b.weight.compareTo(a.weight);
  return (off: off..sort(heaviest), on: on..sort(heaviest));
}

Map<double, int> _tally(List<PlateCount> plates) {
  final out = <double, int>{};
  for (final p in plates) {
    out[p.weight] = (out[p.weight] ?? 0) + p.count;
  }
  return out;
}

/// "45 ×2 · 25": each size once, with its count when there is more than one.
String plateList(List<PlateCount> plates) => plates
    .map((p) => p.count == 1 ? fmt(p.weight) : '${fmt(p.weight)} ×${p.count}')
    .join(' · ');
