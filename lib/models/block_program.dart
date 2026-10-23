enum BlockMethod { doubleProgression, reversePyramid }

enum BlockResponse { unreviewed, stable, aggravated }

/// A routine's immutable enrollment. Calendar dates use local date components.
class BlockProgram {
  BlockProgram({
    required this.id,
    required this.start,
    required this.day,
    required Map<String, BlockExerciseRule> rules,
    this.fifthWeeks = const [],
  }) : rules = Map.unmodifiable(rules);

  final String id;
  final DateTime start;
  final int day;
  final Map<String, BlockExerciseRule> rules;
  final List<int> fifthWeeks;

  int weekOn(DateTime date) =>
      (DateTime.utc(
                date.year,
                date.month,
                date.day,
              ).difference(DateTime.utc(start.year, start.month, start.day)).inDays /
              7)
          .floor() +
      1;
  bool activeOn(DateTime date) => !dateOnly(date).isBefore(dateOnly(start)) && weekOn(date) <= 12;
  bool fifthOn(int week) => week % 4 != 0 && fifthWeeks.contains(week);

  BlockProgram copyWith({DateTime? start, Map<String, BlockExerciseRule>? rules, List<int>? fifthWeeks}) =>
      BlockProgram(
        id: id,
        start: start ?? this.start,
        day: day,
        rules: rules ?? this.rules,
        fifthWeeks: fifthWeeks ?? this.fifthWeeks,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start':
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
    'day': day,
    'rules': rules.map((id, rule) => MapEntry(id, rule.toJson())),
    if (fifthWeeks.isNotEmpty) 'fifthWeeks': fifthWeeks,
  };

  factory BlockProgram.fromJson(Map<String, dynamic> json) {
    final startText = json['start'];
    final start = startText is String ? DateTime.tryParse(startText) : null;
    if (start == null ||
        startText !=
            '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}') {
      throw const FormatException('Invalid program start date');
    }
    final raw = blockMap(json['rules']);
    if (raw.length > 30) throw const FormatException('Invalid program exercises');
    final fifth = json['fifthWeeks'] ?? <dynamic>[];
    if (fifth is! List || fifth.length > 12) throw const FormatException('Invalid optional weeks');
    return BlockProgram(
      id: blockId(json['id']),
      start: start,
      day: blockInt(json['day'], 0, 4),
      rules: raw.map((id, rule) => MapEntry(id, BlockExerciseRule.fromJson(blockMap(rule)))),
      fifthWeeks: List.unmodifiable(fifth.map((week) => blockInt(week, 1, 12))),
    );
  }
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class BlockExerciseRule {
  const BlockExerciseRule({
    this.method = BlockMethod.doubleProgression,
    required this.sets,
    required this.calibrationSets,
    required this.deloadSets,
    required this.minReps,
    required this.maxReps,
    this.incrementKg = 2.26796185,
    this.roundingKg = 2.26796185,
    this.seedKg = 0,
    this.maxWeightKg,
    this.minimumRir = 2,
    this.warmupSets = 0,
    this.optionalMove = 0,
  });

  final BlockMethod method;
  final int sets, calibrationSets, deloadSets, minReps, maxReps;
  final double incrementKg, roundingKg, seedKg;
  final double? maxWeightKg;
  final int minimumRir, warmupSets, optionalMove;

  BlockExerciseRule copyWith({
    double? seedKg,
    double? incrementKg,
    double? roundingKg,
    double? maxWeightKg,
    bool clearCap = false,
  }) => BlockExerciseRule(
    method: method,
    sets: sets,
    calibrationSets: calibrationSets,
    deloadSets: deloadSets,
    minReps: minReps,
    maxReps: maxReps,
    incrementKg: incrementKg ?? this.incrementKg,
    roundingKg: roundingKg ?? this.roundingKg,
    seedKg: seedKg ?? this.seedKg,
    maxWeightKg: clearCap ? null : maxWeightKg ?? this.maxWeightKg,
    minimumRir: minimumRir,
    warmupSets: warmupSets,
    optionalMove: optionalMove,
  );

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'sets': sets,
    'calibrationSets': calibrationSets,
    'deloadSets': deloadSets,
    'minReps': minReps,
    'maxReps': maxReps,
    'incrementKg': incrementKg,
    'roundingKg': roundingKg,
    'seedKg': seedKg,
    if (maxWeightKg != null) 'maxWeightKg': maxWeightKg,
    'minimumRir': minimumRir,
    'warmupSets': warmupSets,
    'optionalMove': optionalMove,
  };

  factory BlockExerciseRule.fromJson(Map<String, dynamic> json) {
    final method = BlockMethod.values.where((m) => m.name == json['method']).firstOrNull;
    if (method == null) throw const FormatException('Invalid exercise progression');
    final sets = blockInt(json['sets'], 1, 12);
    final low = blockInt(json['minReps'], 1, 50);
    final high = blockInt(json['maxReps'], low, 50);
    return BlockExerciseRule(
      method: method,
      sets: sets,
      calibrationSets: blockInt(json['calibrationSets'], 1, sets),
      deloadSets: blockInt(json['deloadSets'], 0, sets),
      minReps: low,
      maxReps: high,
      incrementKg: blockNumber(json['incrementKg'], .001, 100),
      roundingKg: blockNumber(json['roundingKg'], .001, 100),
      seedKg: blockNumber(json['seedKg'], 0, 1000),
      maxWeightKg: json['maxWeightKg'] == null ? null : blockNumber(json['maxWeightKg'], .001, 1000),
      minimumRir: blockInt(json['minimumRir'], 2, 4),
      warmupSets: blockInt(json['warmupSets'], 0, 4),
      optionalMove: blockInt(json['optionalMove'], 0, sets),
    );
  }
}

class BlockTarget {
  const BlockTarget(this.reps, this.weightKg);
  final int reps;
  final double weightKg;
  Map<String, dynamic> toJson() => {'r': reps, 'w': weightKg};
  factory BlockTarget.fromJson(Map<String, dynamic> json) =>
      BlockTarget(blockInt(json['r'], 1, 50), blockNumber(json['w'], 0, 1000));
}

/// Frozen targets travel with the workout, including a restored live session.
class BlockSession {
  BlockSession({
    required this.programId,
    required this.day,
    required this.week,
    required this.minimumRir,
    required this.targets,
    this.reasons = const {},
    this.rules = const {},
    Map<String, BlockResponse>? responses,
  }) : responses = responses ?? {};
  final String programId;
  final int day, week, minimumRir;
  final Map<String, List<BlockTarget>> targets;
  final Map<String, String> reasons;
  final Map<String, BlockExerciseRule> rules;
  final Map<String, BlockResponse> responses;
  bool get deload => week % 4 == 0;

  Map<String, dynamic> toJson() => {
    'id': programId,
    'day': day,
    'week': week,
    'minimumRir': minimumRir,
    'targets': targets.map((id, sets) => MapEntry(id, sets.map((s) => s.toJson()).toList())),
    'reasons': reasons,
    if (rules.isNotEmpty) 'rules': rules.map((id, rule) => MapEntry(id, rule.toJson())),
    'responses': responses.map((id, response) => MapEntry(id, response.name)),
  };

  factory BlockSession.fromJson(Map<String, dynamic> json) {
    final targets = blockMap(json['targets']);
    if (targets.length > 30) throw const FormatException('Too many program targets');
    final parsed = targets.map((id, value) {
      if (value is! List || value.length > 12) throw const FormatException('Invalid program targets');
      return MapEntry(id, value.map((s) => BlockTarget.fromJson(blockMap(s))).toList());
    });
    final responses = blockMap(json['responses'] ?? {});
    final reasons = blockMap(json['reasons'] ?? {});
    if (reasons.values.any((v) => v is! String || v.length > 500)) {
      throw const FormatException('Invalid program explanation');
    }
    return BlockSession(
      programId: blockId(json['id']),
      day: blockInt(json['day'], 0, 4),
      week: blockInt(json['week'], 1, 12),
      minimumRir: blockInt(json['minimumRir'], 2, 4),
      targets: parsed,
      reasons: reasons.cast<String, String>(),
      rules: blockMap(
        json['rules'] ?? {},
      ).map((id, rule) => MapEntry(id, BlockExerciseRule.fromJson(blockMap(rule)))),
      responses: responses.map((id, value) {
        final response = BlockResponse.values.where((r) => r.name == value).firstOrNull;
        if (response == null) throw const FormatException('Invalid program response');
        return MapEntry(id, response);
      }),
    );
  }
}

Map<String, dynamic> blockMap(Object? value) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    throw const FormatException('Invalid program object');
  }
  return value.cast<String, dynamic>();
}

String blockId(Object? value) {
  if (value is! String || value.isEmpty || value.length > 200) {
    throw const FormatException('Invalid program ID');
  }
  return value;
}

int blockInt(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) throw const FormatException('Invalid program integer');
  return value;
}

double blockNumber(Object? value, double min, double max) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw const FormatException('Invalid program load');
  }
  return value.toDouble();
}
