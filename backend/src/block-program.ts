type Check = (condition: unknown, message?: string) => asserts condition;
type RecordValue = Record<string, unknown>;
function record(value: unknown): value is RecordValue {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function integer(value: unknown, min: number, max: number) {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= min &&
    value <= max
  );
}
function number(value: unknown, min: number, max: number) {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= min &&
    value <= max
  );
}
function rules(value: unknown, check: Check) {
  check(
    record(value) && Object.keys(value).length <= 30,
    "Invalid program rules",
  );
  for (const rule of Object.values(value)) {
    check(record(rule), "Invalid program rule");
    check(
      rule.method === "doubleProgression" || rule.method === "reversePyramid",
    );
    check(integer(rule.sets, 1, 12));
    check(integer(rule.calibrationSets, 1, rule.sets as number));
    check(integer(rule.deloadSets, 0, rule.sets as number));
    check(integer(rule.minReps, 1, 50));
    check(integer(rule.maxReps, rule.minReps as number, 50));
    check(number(rule.incrementKg, 0.001, 100));
    check(number(rule.roundingKg, 0.001, 100));
    check(number(rule.seedKg, 0, 1000));
    check(
      rule.maxWeightKg === undefined || number(rule.maxWeightKg, 0.001, 1000),
    );
    check(integer(rule.minimumRir, 2, 4));
    check(integer(rule.warmupSets, 0, 4));
    check(integer(rule.optionalMove, 0, rule.sets as number));
  }
}

/** Optional program metadata uses the existing routine/workout replication envelope. */
export function validateBlockProgram(
  value: unknown,
  workout: boolean,
  exerciseIds: unknown[],
  check: Check,
) {
  if (value === undefined) return;
  check(record(value), "Invalid program");
  check(
    typeof value.id === "string" &&
      value.id.length > 0 &&
      value.id.length <= 200,
  );
  check(integer(value.day, 0, 4));
  if (!workout) {
    check(
      typeof value.start === "string" &&
        /^\d{4}-\d{2}-\d{2}$/.test(value.start),
    );
    const date = new Date(`${value.start}T00:00:00.000Z`);
    check(
      Number.isFinite(date.getTime()) &&
        date.toISOString().slice(0, 10) === value.start,
    );
    rules(value.rules, check);
    check(
      record(value.rules) &&
        Object.keys(value.rules).every((id) => exerciseIds.includes(id)),
    );
    if (value.fifthWeeks !== undefined) {
      check(
        Array.isArray(value.fifthWeeks) &&
          value.fifthWeeks.length <= 12 &&
          value.fifthWeeks.every((week) => integer(week, 1, 12)),
      );
    }
    return;
  }
  check(integer(value.week, 1, 12));
  check(integer(value.minimumRir, 2, 4));
  check(record(value.targets) && Object.keys(value.targets).length <= 30);
  for (const sets of Object.values(value.targets)) {
    check(Array.isArray(sets) && sets.length <= 12);
    for (const set of sets) {
      check(record(set) && integer(set.r, 1, 50) && number(set.w, 0, 1000));
    }
  }
  if (value.rules !== undefined) rules(value.rules, check);
  if (value.responses !== undefined) {
    check(record(value.responses) && Object.keys(value.responses).length <= 30);
    check(
      Object.values(value.responses).every((r) =>
        ["unreviewed", "stable", "aggravated"].includes(String(r)),
      ),
    );
  }
  if (value.reasons !== undefined) {
    check(record(value.reasons) && Object.keys(value.reasons).length <= 30);
    check(
      Object.values(value.reasons).every(
        (r) => typeof r === "string" && r.length <= 500,
      ),
    );
  }
}
