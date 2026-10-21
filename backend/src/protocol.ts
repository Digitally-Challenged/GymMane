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
