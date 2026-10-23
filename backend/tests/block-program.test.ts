import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { parsePush } from "../src/protocol.js";

const rule = {
  method: "doubleProgression",
  sets: 3,
  calibrationSets: 2,
  deloadSets: 1,
  minReps: 8,
  maxReps: 12,
  incrementKg: 2.5,
  roundingKg: 2.5,
  seedKg: 0,
  minimumRir: 2,
  warmupSets: 1,
  optionalMove: 0,
};
const program = {
  id: randomUUID(),
  start: "2026-01-05",
  day: 0,
  rules: { EIeI8Vf: rule },
};
function parse(value: unknown) {
  const id = randomUUID();
  return parsePush({
    schemaVersion: 1,
    operations: [
      {
        operationId: randomUUID(),
        entityType: "routine",
        entityId: id,
        baseRevision: 0,
        deleted: false,
        payload: {
          id,
          n: "Synthetic program",
          ex: ["EIeI8Vf"],
          program: value,
        },
      },
    ],
  });
}
test("program configuration survives the existing routine protocol", () => {
  assert.deepEqual(parse(program)[0].payload?.program, program);
});
test("malformed program rules and impossible calendar dates are rejected", () => {
  for (const invalid of [
    null,
    [],
    { ...program, start: "2026-02-30" },
    { ...program, day: 5 },
    { ...program, rules: { unreferenced: rule } },
    { ...program, fifthWeeks: [0] },
    { ...program, rules: { EIeI8Vf: { ...rule, incrementKg: -1 } } },
    { ...program, rules: { EIeI8Vf: { ...rule, maxReps: 5 } } },
  ]) {
    assert.throws(() => parse(invalid), { status: 400 });
  }
});

function parseWorkout(program: unknown) {
  const id = randomUUID();
  return parsePush({
    schemaVersion: 1,
    operations: [
      {
        operationId: randomUUID(),
        entityType: "workout",
        entityId: id,
        baseRevision: 0,
        deleted: false,
        payload: {
          id,
          d: "2026-01-23T12:00:00.000Z",
          dur: 1200,
          ex: [],
          program,
        },
      },
    ],
  });
}
const snapshot = {
  id: program.id,
  day: 0,
  week: 3,
  minimumRir: 2,
  targets: { EIeI8Vf: [{ r: 8, w: 40 }] },
  responses: { EIeI8Vf: "stable" },
  reasons: { EIeI8Vf: "Synthetic target" },
  rules: { EIeI8Vf: rule },
};
test("partial workouts preserve frozen targets even for unfinished exercises", () => {
  assert.deepEqual(parseWorkout(snapshot)[0].payload?.program, snapshot);
});
test("invalid workout prescriptions or responses cannot enter program history", () => {
  for (const invalid of [
    { ...snapshot, week: 13 },
    { ...snapshot, targets: { EIeI8Vf: [{ r: 8, w: -1 }] } },
    { ...snapshot, responses: { EIeI8Vf: "unknown" } },
    { ...snapshot, minimumRir: 0 },
  ]) {
    assert.throws(() => parseWorkout(invalid), { status: 400 });
  }
});
