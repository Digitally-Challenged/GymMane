import '../theme/plate_palette.dart';

class GymPlace {
  const GymPlace({
    required this.id,
    required this.name,
    required this.equipment,
    this.plates = const {},
    this.bar,
    this.collarKg = 0,
    this.colourBase = PlateColourBase.coloured,
    this.customColours = false,
    this.plateColours = const {},
  });

  final String id;
  final String name;
  final Set<String> equipment;
  final Map<double, int> plates;
  final double? bar;

  /// Weight of one collar in kg. Both collars count, so the load is twice this.
  final double collarKg;
  final PlateColourBase colourBase;
  final bool customColours;

  /// Per-size colour overrides: kg size to ARGB value. Kept while Custom is off.
  final Map<double, int> plateColours;

  GymPlace copyWith({
    String? name,
    Set<String>? equipment,
    Map<double, int>? plates,
    double? bar,
    bool clearBar = false,
    double? collarKg,
    PlateColourBase? colourBase,
    bool? customColours,
    Map<double, int>? plateColours,
  }) =>
      GymPlace(
        id: id,
        name: name ?? this.name,
        equipment: equipment ?? this.equipment,
        plates: plates ?? this.plates,
        bar: clearBar ? null : (bar ?? this.bar),
        collarKg: collarKg ?? this.collarKg,
        colourBase: colourBase ?? this.colourBase,
        customColours: customColours ?? this.customColours,
        plateColours: plateColours ?? this.plateColours,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'e': equipment.toList(),
        if (plates.isNotEmpty) 'p': plates.map((k, v) => MapEntry(k.toString(), v)),
        if (bar != null) 'b': bar,
        if (collarKg > 0) 'cl': collarKg,
        if (colourBase == PlateColourBase.iron) 'cb': 'iron',
        if (customColours) 'cc': true,
        if (plateColours.isNotEmpty) 'pc': plateColours.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory GymPlace.fromJson(Map<String, dynamic> j) => GymPlace(
        id: (j['id'] ?? '') as String,
        name: (j['n'] ?? '') as String,
        equipment: ((j['e'] as List?) ?? const []).cast<String>().toSet(),
        plates: ((j['p'] as Map?) ?? const {})
            .map((k, v) => MapEntry(double.parse(k as String), (v as num).toInt())),
        bar: (j['b'] as num?)?.toDouble(),
        collarKg: (j['cl'] as num?)?.toDouble() ?? 0,
        colourBase: j['cb'] == 'iron' ? PlateColourBase.iron : PlateColourBase.coloured,
        customColours: j['cc'] == true,
        plateColours: ((j['pc'] as Map?) ?? const {})
            .map((k, v) => MapEntry(double.parse(k as String), (v as num).toInt())),
      );
}
