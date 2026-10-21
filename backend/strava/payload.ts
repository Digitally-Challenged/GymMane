import { coreMovements } from "./core-movements.js";
import { object, workoutElapsedSeconds } from "../src/protocol.js";
// Exact identifiers from https://developers.strava.com/docs/uploads/ (2026-10-20).
// IDs, not user-editable names, determine movement. Unmapped exercises reject the
// whole export so that neither invented exercises nor silently incomplete sets ship.
const groups: Record<string, string[]> = {
  MACHINE_CHEST_PRESS: [
    "machine-chest-press",
    "arsenal-forge-x-wide-chest-press",
    "arsenal-forge-x-converging-chest-press",
    "arsenal-reloaded-iso-flat-press",
    "arsenal-reloaded-standing-chest-press",
    "arsenal-reloaded-vertical-chest-press",
  ],
  MACHINE_INCLINE_CHEST_PRESS: ["arsenal-reloaded-iso-incline-press"],
  MACHINE_ISOLATERAL_HIGH_ROW: [
    "arsenal-forge-x-scorpion-high-row",
    "arsenal-reloaded-multi-grip-high-row",
  ],
  MACHINE_PULLOVER: ["arsenal-m-1-lat-pullover"],
  T_BAR_ROW: [
    "t-bar-row",
    "arsenal-alpha-bent-over-row-bench-with-special-bar",
    "arsenal-reloaded-t-bar-row",
  ],
  BACK_EXTENSION: ["back-extension", "arsenal-alpha-45-degree-back-extension"],
  MACHINE_LEG_PRESS: [
    "leg-press",
    "arsenal-forge-x-pivot-leg-press",
    "arsenal-reloaded-vertical-leg-press",
    "arsenal-reloaded-linear-leg-press",
    "arsenal-reloaded-bilateral-leg-press",
    "arsenal-reloaded-horizontal-leg-press",
  ],
  STANDING_LEG_CURL: ["arsenal-m-1-standing-leg-curl"],
  LEG_CURL_GENERIC: [
    "leg-curl",
    "arsenal-m-1-lying-leg-curl",
    "arsenal-forge-x-lying-leg-curl",
  ],
  MACHINE_LEG_CURL_SEATED: ["arsenal-reloaded-seated-leg-curl"],
  MACHINE_SEATED_SHOULDER_PRESS: [
    "machine-shoulder-press",
    "arsenal-forge-x-shoulder-press",
    "arsenal-reloaded-iso-converging-shoulder-press",
  ],
  SHOULDER_PRESS_GENERIC: ["arsenal-reloaded-viking-press"],
  MACHINE_SEATED_ROW: [
    "machine-row",
    "arsenal-forge-x-seated-row",
    "arsenal-forge-x-diverging-row",
    "arsenal-reloaded-vertical-row",
    "arsenal-reloaded-iso-multi-row",
    "arsenal-reloaded-lever-row",
  ],
  SEATED_CABLE_ROW: ["cable-row", "arsenal-m-1-basic-trainer-seated-row"],
  MACHINE_TRICEP_EXTENSION: [
    "arsenal-forge-x-seated-tricep-extension",
    "arsenal-m-1-overhead-tricep-extension",
  ],
  TRICEPS_EXTENSION_GENERIC: ["arsenal-reloaded-triceps-kickback"],
  MACHINE_GLUTE_KICKBACK: ["arsenal-m-1-glute-isolator"],
  GLUTE_HAM_RAISE: ["arsenal-alpha-glute-ham-developer"],
  MACHINE_BICEP_CURL: [
    "arsenal-m-1-bicep-curl",
    "arsenal-forge-x-seated-iso-bicep-curl",
  ],
  CURL_GENERIC: ["arsenal-alpha-standing-preacher-curl-bench"],
  MACHINE_CHEST_FLY: [
    "pec-deck",
    "arsenal-forge-x-upright-decline-fly",
    "arsenal-m-1-pec-fly",
    "arsenal-reloaded-incline-fly",
  ],
  LATERAL_RAISE_GENERIC: ["arsenal-m-1-standing-lateral-raise"],
  CALF_RAISE_GENERIC: ["arsenal-m-1-donkey-calf-raise"],
  STANDING_CALF_RAISE: ["calf-raise", "arsenal-m-1-standing-calf-raise"],
  SEATED_CALF_RAISE: ["arsenal-reloaded-seated-calf-raise"],
  MACHINE_LEG_EXTENSION: [
    "leg-extension",
    "arsenal-m-1-seated-leg-extension-machine",
    "arsenal-forge-x-leg-extension",
    "arsenal-reloaded-leg-extension",
  ],
  LAT_PULLDOWN: [
    "lat-pulldown",
    "arsenal-m-1-lat-pulldown",
    "arsenal-m-1-basic-trainer-lat-pulldown",
    "arsenal-reloaded-iso-lat-pulldown",
    "arsenal-reloaded-multi-grip-pulldown",
  ],
  SISSY_SQUAT: ["arsenal-alpha-sissy-squat-stand"],
  MACHINE_HIP_ADDUCTION: ["arsenal-m-1-hip-adduction"],
  MACHINE_HIP_ABDUCTION: ["arsenal-m-1-hip-abduction"],
  MACHINE_REAR_DELT_REVERSE_FLY: ["arsenal-m-1-rear-delt-fly"],
  HANGING_KNEE_RAISE: ["arsenal-alpha-vertical-knee-raise"],
  BODY_WEIGHT_DIP: ["dips", "arsenal-alpha-parallel-bar-dip"],
  SLED_PUSH: ["arsenal-alpha-sled-push"],
  SLED_PULL: ["arsenal-alpha-sled-pull"],
  SMITH_MACHINE_ROW: ["arsenal-reloaded-linear-smith-row"],
  SMITH_MACHINE_OVERHEAD_PRESS: [
    "arsenal-reloaded-linear-smith-shoulder-press",
  ],
  SQUAT_GENERIC: ["arsenal-reloaded-power-squat"],
  MACHINE_HACK_SQUAT: ["hack-squat", "arsenal-reloaded-linear-hack-squat"],
  GLUTE_BRIDGE: ["arsenal-reloaded-glute-bridge"],
  BELT_SQUAT: ["arsenal-reloaded-belt-squat"],
  PENDULUM_SQUAT: ["arsenal-reloaded-pendulum-squat"],
  SEATED_DIP_MACHINE: ["arsenal-reloaded-seated-dip"],
  ROMANIAN_DEADLIFTS: ["arsenal-reloaded-multi-flex-romanian-deadlift"],
  LUNGE_GENERIC: ["arsenal-reloaded-multi-flex-split-squat"],
  SHRUG_GENERIC: ["arsenal-reloaded-multi-flex-shrug"],
  BARBELL_BENCH_PRESS: ["bench-press"],
  BARBELL_BACK_SQUAT: ["squat"],
  BARBELL_DEADLIFT: ["deadlift"],
  PLANK_HOLD: ["plank"],
  DUMBBELL_BENCH_PRESS: ["db-bench-press"],
};
export const movementMap = new Map([
  ...Object.entries(coreMovements),
  ...Object.entries(groups).flatMap(([type, ids]) =>
    ids.map((id) => [id, type] as const),
  ),
]);
export class UnsupportedWorkout extends Error {}
export interface StrengthSet {
  exercise_type: string;
  repetitions?: number;
  weight?: number;
  duration?: number;
}
export interface StrengthPayload {
  version: "1.0";
  start_time: string;
  utc_offset: number;
  elapsed_time: number;
  active_time: number;
  creator: { name: string };
  sets: StrengthSet[];
}
export function strengthPayload(raw: unknown): StrengthPayload {
  const fail = (message: string): never => {
    throw new UnsupportedWorkout(message);
  };
  if (!object(raw) || raw.origin !== "gymmane")
    return fail("Only GymMane-origin workouts can be exported");
  const elapsed = workoutElapsedSeconds(raw);
  if (elapsed === null) return fail("Actual workout start timing is required");
  if (
    !Number.isSafeInteger(raw.dur) ||
    (raw.dur as number) <= 0 ||
    (raw.dur as number) > 604800
  )
    return fail("A recorded positive duration is required");
  const offset = raw.utcOffsetSeconds;
  if (!Number.isInteger(offset) || Math.abs(offset as number) > 50400)
    return fail("Recorded UTC offset is required");
  if (!Array.isArray(raw.ex)) return fail("Missing exercises");
  const sets: StrengthSet[] = [];
  for (const ex of raw.ex) {
    if (!object(ex) || typeof ex.id !== "string" || !Array.isArray(ex.s))
      return fail("Invalid exercise");
    const type = movementMap.get(ex.id);
    if (!type && ex.s.length) return fail(`Unsupported exercise: ${ex.id}`);
    for (const s of ex.s) {
      if (
        !object(s) ||
        !Number.isSafeInteger(s.r) ||
        (s.r as number) < 0 ||
        typeof s.w !== "number" ||
        !Number.isFinite(s.w) ||
        s.w < 0
      )
        return fail("Invalid repetitions or weight");
      if (s.km !== undefined && s.km !== null)
        return fail("Distance sets are not strength exports");
      if (
        s.t !== undefined &&
        s.t !== null &&
        (!Number.isSafeInteger(s.t) || (s.t as number) <= 0)
      )
        return fail("Invalid timed set");
      if (s.r === 0 && !s.t)
        return fail("Set has no recorded repetitions or duration");
      sets.push({
        exercise_type: type!,
        ...(s.r ? { repetitions: s.r as number } : {}),
        ...(s.w > 0 ? { weight: s.w } : {}),
        ...(s.t ? { duration: s.t as number } : {}),
      });
    }
  }
  if (!sets.length || sets.length > 1000)
    return fail("Export requires between 1 and 1000 sets");
  return {
    version: "1.0",
    start_time: raw.startedAt as string,
    utc_offset: offset as number,
    // Strava JSON documents elapsed_time and optional active_time separately:
    // https://developers.strava.com/docs/uploads/#json---strength-training-limited
    // Integer seconds round up, including the validation tolerance of one second.
    elapsed_time: Math.max(Math.ceil(elapsed), raw.dur as number),
    active_time: raw.dur as number,
    creator: { name: "GymMane" },
    sets,
  };
}
