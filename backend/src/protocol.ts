export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}
export const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export type JsonObject = Record<string, unknown>;
export interface Operation {
  operationId: string;
  entityType: "workout" | "routine";
  entityId: string;
  baseRevision: number;
  deleted: boolean;
  payload: JsonObject | null;
}
export interface Entity {
  entityType: Operation["entityType"];
  entityId: string;
  revision: number;
  deleted: boolean;
  payload: JsonObject | null;
  cursor: string;
}
export interface Result {
  operationId: string;
  status: "accepted" | "conflict";
  entity: Entity;
}
export function assert(
  value: unknown,
  message = "Invalid request",
): asserts value {
  if (!value) throw new HttpError(400, message);
}
export function object(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function finite(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value);
}
function set(value: unknown, planned = false) {
  assert(object(value));
  for (const key of ["r", "w"])
    assert((planned && value[key] === undefined) || finite(value[key]));
  for (const key of ["k", "e", "t", "km"])
    assert(
      value[key] === undefined || value[key] === null || finite(value[key]),
    );
}
// Dart emits three or six fractional digits, and no suffix for legacy local
// dates. Never use Date.parse: it accepts prose and normalizes invalid days.
function workoutDate(value: unknown): bigint | null {
  if (typeof value !== "string") return null;
  const match =
    /^([0-9]{4}|-[0-9]{4}|[+-][0-9]{6})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,6}))?(Z)?$/.exec(
      value,
    );
  if (!match || match[0] !== value) return null;
  const [, year, month, day, hour, minute, second, fraction = ""] = match;
  const y = Number(year),
    m = Number(month),
    d = Number(day);
  const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (
    m < 1 ||
    m > 12 ||
    d < 1 ||
    d > days[m - 1] ||
    Number(hour) > 23 ||
    Number(minute) > 59 ||
    Number(second) > 59
  )
    return null;
  // Check the shared DateTime range without losing microseconds or interpreting
  // timezone-less legacy values using the server's local timezone.
  const date = new Date(0);
  date.setUTCFullYear(y, m - 1, d);
  date.setUTCHours(Number(hour), Number(minute), Number(second), 0);
  const micros = BigInt(fraction.padEnd(6, "0"));
  if (!Number.isFinite(date.getTime())) return null;
  const timestamp = BigInt(date.getTime()) * 1000n + micros;
  return timestamp <= 8640000000000000000n ? timestamp : null;
}

// Actual timing requires unambiguous UTC instants. Legacy local dates remain
// accepted for sync when startedAt is absent, but cannot support export.
export function workoutElapsedSeconds(value: JsonObject): number | null {
  if (
    typeof value.startedAt !== "string" ||
    !value.startedAt.endsWith("Z") ||
    typeof value.d !== "string" ||
    !value.d.endsWith("Z")
  )
    return null;
  const start = workoutDate(value.startedAt),
    end = workoutDate(value.d);
  if (
    start === null ||
    end === null ||
    start > end ||
    !Number.isSafeInteger(value.dur) ||
    (value.dur as number) < 0
  )
    return null;
  const elapsed = end - start;
  // Allow one second for integer active-duration rounding at client boundaries.
  // Compare microseconds so even a sub-millisecond start after end is rejected.
  if (BigInt(value.dur as number) * 1000000n > elapsed + 1000000n) return null;
  return Number(elapsed) / 1000000;
}
// Reserved IDs from the shipped Flutter exercise catalog. The catalog parity
// regression checks every catalog ID so new built-ins cannot become overridable.
const builtinExerciseIds = new Set(
  `
0CXGHya 0jp9Rlz 0lQnxMZ 1V1gj1u 1bQkKZK 1kB3Wmk 25GPyDY 2IxROQ1 2NImIAG 33AzZeV 3TZduzM
3ZflifB 3d7wHyd 3eGE2JC 4dUn2iv 5VCj6iH 61GrD55 67n3r98 6HiHHe0 6YUfHPL 6bOA1Oi 72BC5Za
7E06s6d 7I6LNUG 7M66AVi 7OeHptV 7jGOBF3 7vG5o25 7xeukSt 7zdxRTl 82LxxkW 8ozhUIZ 8urJS9b
903mzG8 9E25EOx 9WTm7dq 9XjtHvS A6wtbuL A9qxk2F BJ0Hz5L BbfB8Gb C5jncD2 CqhoytW Db7eEgw
DsgkuIt DwhEmmE EIeI8Vf EZeDVzO Eg98Ft9 FkBIE6a G08RZcQ G7xoEzr GWoKnIm Gk1r408 GrO65fd
HEJ6DIX HMzLjXx HPlPoQA Hj4FOCd Hx1WC8I I4hDWkc IENzBdA IeDEXTe IpONWYv J6Dx1Mu J74XlNf
JsKq9so KgI0tqW Kpajagk Kyd9Rz5 LMGXZn8 LNE3wfo LmaFNZS LsZkfU6 MU9HnE7 MvQPqVW NJzBsGJ
NNoHCEA NbVPDMW NlfIbzq OM46QHm OTgkHwR OUQ0ZyW PAgTVaK PSlvNMs PbzNu7c PdmaD0N QChZi3x
QOA0FD0 RRWFUcw RVwzP10 RqOtqD7 RrLske5 S9zHIvU SGY8Zui Ser9eQp SpYC0Kp T2mxWqc TFqbd8t
UfePqpx VBAWRPG VLYXo8S VO2qeJg VW88JNd W31mMjd W9pFVv1 WLvTAv5 WW95auq WbNq5Xu WcHl7ru
X6C6i5Y XVDdcoj XlZ4lAC Xy4jlWA Y7YcmIJ ZsiqXYa ZuPXtCK Zwiw7XR aaXr7ld active-hang
aqvSOQE arch-hang arsenal-alpha-45-degree-back-extension
arsenal-alpha-bent-over-row-bench-with-special-bar arsenal-alpha-glute-ham-developer
arsenal-alpha-parallel-bar-dip arsenal-alpha-sissy-squat-stand arsenal-alpha-sled-pull
arsenal-alpha-sled-push arsenal-alpha-standing-preacher-curl-bench
arsenal-alpha-vertical-knee-raise arsenal-forge-x-converging-chest-press
arsenal-forge-x-diverging-row arsenal-forge-x-leg-extension arsenal-forge-x-lying-leg-curl
arsenal-forge-x-pivot-leg-press arsenal-forge-x-scorpion-high-row
arsenal-forge-x-seated-iso-bicep-curl arsenal-forge-x-seated-row
arsenal-forge-x-seated-tricep-extension arsenal-forge-x-shoulder-press
arsenal-forge-x-upright-decline-fly arsenal-forge-x-wide-chest-press
arsenal-m-1-basic-trainer-lat-pulldown arsenal-m-1-basic-trainer-seated-row
arsenal-m-1-bicep-curl arsenal-m-1-donkey-calf-raise arsenal-m-1-glute-isolator
arsenal-m-1-hip-abduction arsenal-m-1-hip-adduction arsenal-m-1-lat-pulldown
arsenal-m-1-lat-pullover arsenal-m-1-lying-leg-curl arsenal-m-1-overhead-tricep-extension
arsenal-m-1-pec-fly arsenal-m-1-rear-delt-fly arsenal-m-1-seated-leg-extension-machine
arsenal-m-1-standing-calf-raise arsenal-m-1-standing-lateral-raise
arsenal-m-1-standing-leg-curl arsenal-reloaded-belt-squat
arsenal-reloaded-bilateral-leg-press arsenal-reloaded-glute-bridge
arsenal-reloaded-hip-hack-press arsenal-reloaded-horizontal-leg-press
arsenal-reloaded-incline-fly arsenal-reloaded-iso-converging-shoulder-press
arsenal-reloaded-iso-flat-press arsenal-reloaded-iso-incline-press
arsenal-reloaded-iso-lat-pulldown arsenal-reloaded-iso-multi-row
arsenal-reloaded-leg-extension arsenal-reloaded-lever-row
arsenal-reloaded-linear-hack-squat arsenal-reloaded-linear-leg-press
arsenal-reloaded-linear-smith-row arsenal-reloaded-linear-smith-shoulder-press
arsenal-reloaded-multi-flex-romanian-deadlift arsenal-reloaded-multi-flex-shrug
arsenal-reloaded-multi-flex-split-squat arsenal-reloaded-multi-grip-high-row
arsenal-reloaded-multi-grip-pulldown arsenal-reloaded-pendulum-squat
arsenal-reloaded-posterior-chain-developer arsenal-reloaded-power-squat
arsenal-reloaded-seated-calf-raise arsenal-reloaded-seated-dip
arsenal-reloaded-seated-leg-curl arsenal-reloaded-standing-chest-press
arsenal-reloaded-t-bar-row arsenal-reloaded-triceps-kickback
arsenal-reloaded-vertical-chest-press arsenal-reloaded-vertical-leg-press
arsenal-reloaded-vertical-row arsenal-reloaded-viking-press assault-bike
assisted-pistol-squat assisted-squat bJYHBIN bZq4bwK band-biceps-curl band-calf-raise
band-chest-fly band-pull-apart band-reverse-fly band-upright-row banded-clamshell
banded-dead-bug banded-donkey-kick banded-face-pull banded-fire-hydrant banded-frog-pump
banded-glute-bridge banded-hip-thrust banded-kickback banded-lat-pulldown
banded-lateral-walk banded-monster-walk banded-nordic-curl banded-nordic-curl-negative
banded-pallof-press banded-row banded-seated-hip-abduction banded-squat
banded-standing-hip-abduction banded-woodchop barbell-deficit-deadlift barbell-floor-press
barbell-incline-triceps-extension barbell-lunge barbell-paused-bench-press
barbell-paused-squat barbell-pin-squat barbell-reverse-lunge barbell-seal-row
barbell-seated-overhead-triceps-extension barbell-spoto-press barbell-step-up
barbell-z-press battle-ropes bear-crawl bear-plank beginner-shrimp-squat belt-squat
bench-leg-raise bicycle-crunch bird-dog bodyweight-romanian-deadlift
bodyweight-single-leg-deadlift bulgarian-split-squat burpee butterfly-stretch c8f5cSY
cA9FuWG cable-bayesian-curl cable-behind-the-back-lateral-raise
cable-bent-over-rear-delt-raise cable-cross-body-triceps-extension cable-external-rotation
cable-high-to-low-fly cable-internal-rotation cable-katana-triceps-extension
cable-low-to-high-fly cable-lying-triceps-extension cable-pallof-hold cable-preacher-curl
cable-rear-delt-row cable-reverse-wrist-curl cable-seated-chest-fly cable-standing-crunch
cable-standing-hip-abduction cable-upright-row cable-wrist-curl captains-chair-knee-raise
cat-cow-stretch chair-dip childs-pose clamshell close-grip-lat-pulldown commando-pull-up
crab-walk cross-body-crunch cross-body-hammer-curl cross-body-shoulder-stretch
curtsy-lunge cycling dG5Smob dG7tG5y dead-bug dead-hang-hold decline-chest-press-machine
decline-push-up deficit-reverse-lunge donkey-kick doorway-chest-stretch dragon-flag
dumbbell-curtsy-lunge dumbbell-deficit-romanian-deadlift dumbbell-floor-press
dumbbell-glute-bridge dumbbell-hip-thrust dumbbell-lateral-lunge
dumbbell-lying-triceps-extension dumbbell-paused-bench-press dumbbell-preacher-curl
dumbbell-reverse-curl dumbbell-seal-row dumbbell-spider-curl dumbbell-squat
dumbbell-squeeze-press dumbbell-sumo-deadlift dumbbell-sumo-squat dumbbell-upright-row
dumbbell-z-press e4aFmFY eZyBC3j ecl28tP elliptical fUBheHs fZFZ704 face-pull
feet-elevated-pike-push-up fire-hydrant flat-bench-cable-fly flutter-kick frog-pump
front-foot-elevated-split-squat fy7Tgy4 gFyFj9z gGNQmVt gfk9kD4 glute-bridge
glute-bridge-march goJ6ezq gvsWLQw hBGWILP hack-squat-machine half-burpee
half-kneeling-pallof-press hamstring-stretch handstand-push-up heel-elevated-goblet-squat
high-knees hiking hindu-push-up hip-abduction-machine hip-adduction-machine hip-airplane
hip-thrust hl8DUh8 hollow-body-hold hollow-rock iPm26QU iZop9xO ila4NZS inchworm
incline-chest-press-machine incline-dumbbell-curl incline-dumbbell-fly
incline-dumbbell-hammer-press incline-push-up incline-row intermediate-shrimp-squat
jump-rope jumping-jack kTbSH9h kettlebell-farmer-carry kettlebell-front-squat
kettlebell-goblet-squat kettlebell-high-pull kettlebell-overhead-press
kettlebell-overhead-tricep-extension kettlebell-push-press kettlebell-reverse-lunge
kettlebell-romanian-deadlift kettlebell-russian-twist kettlebell-shrug
kettlebell-side-bend kettlebell-single-arm-row kettlebell-single-leg-deadlift
kettlebell-sumo-deadlift kettlebell-swing kiJ4Z2K knee-push-up kneeling-hip-flexor-stretch
ktsFQAZ l-sit-hold l-sit-pull-up lBDjFxJ landmine-press landmine-romanian-deadlift
landmine-squat lateral-shuffle leg-extension leg-swings-stretch lying-hamstring-walkout
lying-leg-raise lying-rear-lateral-raise mExgrF9 machine-biceps-curl
machine-glute-kickback machine-lateral-raise meadows-row mnzcrIB mountain-climber mweqJin
myfUsKf nFUwqG6 nUwVh7b negative-dip negative-pull-up neutral-grip-pull-up nordic-curl
ns0SIbU one-arm-dumbbell-row otqIxU4 outdoor-cycling outdoor-hike outdoor-run outdoor-walk
pallof-press parallel-bar-support-hold pec-deck pike-push-up pistol-squat plank-hold
plank-jack plank-shoulder-tap prone-t-raise pseudo-planche-push-up qKBpF7I qOgPVf6 qXTaZnJ
qaZVsGk qx4fgX7 r0z6xzQ rNG1dip rNG2pus rNG3fly rNG4tri rNG5pul rNG6chi rNG7row rNG8fac
rNG9cur rNGaham rNGbrol rNGclsi rNGdsup rNGemus reverse-grip-bench-press
reverse-grip-lat-pulldown reverse-grip-triceps-pushdown reverse-hyperextension
reverse-lunge reverse-snow-angel rope-tricep-pushdown rowing running s7HX1BY s8nrDXF
scapular-push-up seal-jack seated-dumbbell-curl seated-forward-fold-stretch
seated-leg-curl shrimp-squat side-lying-leg-raise side-plank-hip-dip side-plank-hold
single-arm-cable-curl single-arm-cable-lat-pulldown single-arm-cable-pushdown
single-arm-cable-row single-arm-dumbbell-bench-press single-arm-dumbbell-shoulder-press
single-arm-dumbbell-tricep-extension single-dumbbell-skullcrusher single-leg-box-squat
single-leg-glute-bridge single-leg-romanian-deadlift skater-hop skater-squat skierg
slDvUAU smith-incline-bench-press smith-machine-bulgarian-split-squat
smith-machine-reverse-lunge smith-upright-row sprawl squat-thrust
stability-ball-hamstring-curl stair-climber standing-quad-stretch straight-arm-pulldown
superman superman-hold swim swimming tBWXbIT tate-press towel-pull-up towel-row
trap-bar-deadlift treadmill-incline-walk trqKQv2 typewriter-push-up u27Kcdz u2X71Np
u5ESqzH uKyN64F uTBt1HV uWpxD4v upright-row v-bar-pushdown v-up v1qBec9 vR1vold
vertical-row wQ2c4XD wWFspEi walking wall-calf-stretch wall-handstand-push-up wall-push-up
wall-sit wall-walk weighted-inverted-row weighted-shrimp-squat wfotm7S
wide-grip-barbell-curl wide-grip-lat-pulldown wide-push-up wide-row wigSg76
worlds-greatest-stretch wrist-prep x6KpKpq xHKN2s8 xNrS20v xXm4nYq xdYPUtE yg8Totb ykUOVze
yn8yg1r yuris-shoulder-band-warmup ywaNfuh yz9nUhF zG0zs85 zottman-curl
`
    .trim()
    .split(/\s+/),
);

function exerciseDefinitions(value: unknown, referenced: unknown[]) {
  if (value === undefined || value === null) return;
  assert(object(value), "Invalid exercise definitions");
  for (const [id, definition] of Object.entries(value)) {
    assert(
      id.length > 0 &&
        referenced.includes(id) &&
        !builtinExerciseIds.has(id) &&
        object(definition) &&
        definition.id === id &&
        typeof definition.n === "string" &&
        definition.n.trim().length > 0 &&
        typeof definition.p === "string" &&
        definition.p.length > 0,
      "Invalid custom exercise dependency",
    );
    for (const key of ["e", "d"])
      assert(
        definition[key] === undefined || typeof definition[key] === "string",
      );
    for (const key of ["s", "st", "a"])
      assert(
        definition[key] === undefined ||
          (Array.isArray(definition[key]) &&
            definition[key].every((v) => typeof v === "string")),
      );
    assert(
      definition.k === undefined ||
        ["", "time", "cardio"].includes(definition.k as string),
    );
    assert(
      definition.ty === undefined ||
        ["", "strength", "calisthenics", "cardio", "stretch"].includes(
          definition.ty as string,
        ),
    );
  }
}

function payload(value: JsonObject, type: Operation["entityType"], id: string) {
  assert(typeof value.id === "string" && value.id.toLowerCase() === id);
  assert(Array.isArray(value.ex));
  assert(
    value.n === undefined || value.n === null || typeof value.n === "string",
  );
  if (type === "workout") {
    assert(workoutDate(value.d) !== null, "Invalid workout ISO timestamp");
    assert(Number.isSafeInteger(value.dur) && (value.dur as number) >= 0);
    if (value.startedAt !== undefined && value.startedAt !== null)
      assert(
        workoutElapsedSeconds(value) !== null,
        "Invalid workout start timing",
      );
    assert(
      value.r === undefined || value.r === null || typeof value.r === "string",
    );
    for (const exercise of value.ex) {
      assert(
        object(exercise) &&
          typeof exercise.id === "string" &&
          typeof exercise.n === "string" &&
          typeof exercise.p === "string" &&
          Array.isArray(exercise.s),
      );
      exercise.s.forEach((s) => set(s));
    }
  } else {
    assert(
      typeof value.n === "string" &&
        value.ex.every((x) => typeof x === "string"),
    );
    exerciseDefinitions(value.exerciseDefinitions, value.ex);
    for (const key of ["s", "r"])
      if (value[key] !== undefined) {
        assert(object(value[key]));
        assert(Object.values(value[key]).every(Number.isSafeInteger));
      }
    if (value.c !== undefined)
      assert(
        Array.isArray(value.c) && value.c.every((x) => typeof x === "string"),
      );
    for (const key of ["g", "method"])
      assert(value[key] === undefined || typeof value[key] === "string");
    assert(value.k === undefined || Number.isSafeInteger(value.k));
    if (value.p !== undefined) {
      assert(object(value.p));
      for (const sets of Object.values(value.p)) {
        assert(Array.isArray(sets));
        sets.forEach((s) => set(s, true));
      }
    }
  }
}
export function parsePush(body: unknown): Operation[] {
  assert(
    object(body) && body.schemaVersion === 1 && Array.isArray(body.operations),
  );
  assert(
    Object.keys(body).every((k) => ["schemaVersion", "operations"].includes(k)),
  );
  if (body.operations.length > 100)
    throw new HttpError(413, "Maximum 100 operations");
  return body.operations.map((raw) => {
    assert(object(raw));
    assert(
      Object.keys(raw).length === 6 &&
        Object.keys(raw).every((k) =>
          [
            "operationId",
            "entityType",
            "entityId",
            "baseRevision",
            "deleted",
            "payload",
          ].includes(k),
        ),
    );
    assert(typeof raw.operationId === "string" && uuid.test(raw.operationId));
    assert(typeof raw.entityId === "string" && uuid.test(raw.entityId));
    assert(raw.entityType === "workout" || raw.entityType === "routine");
    assert(
      Number.isSafeInteger(raw.baseRevision) &&
        (raw.baseRevision as number) >= 0,
    );
    assert(typeof raw.deleted === "boolean");
    assert(raw.deleted ? raw.payload === null : object(raw.payload));
    if (Buffer.byteLength(JSON.stringify(raw.payload)) > 65536)
      throw new HttpError(413, "Payload exceeds 64 KiB");
    const op = {
      ...raw,
      operationId: raw.operationId.toLowerCase(),
      entityId: raw.entityId.toLowerCase(),
    } as unknown as Operation;
    if (op.payload) payload(op.payload, op.entityType, op.entityId);
    return op;
  });
}
export function parsePull(url: URL) {
  assert(
    [...url.searchParams.keys()].every((k) => ["cursor", "limit"].includes(k)),
  );
  assert(
    url.searchParams.getAll("cursor").length <= 1 &&
      url.searchParams.getAll("limit").length <= 1,
  );
  const cursor = url.searchParams.get("cursor") ?? "0";
  const rawLimit = url.searchParams.get("limit") ?? "100";
  assert(
    /^(0|[1-9][0-9]{0,18})$/.test(cursor) &&
      BigInt(cursor) <= 9223372036854775807n,
  );
  assert(/^[1-9][0-9]{0,2}$/.test(rawLimit));
  const limit = Number(rawLimit);
  assert(limit <= 100);
  return { cursor, limit };
}
