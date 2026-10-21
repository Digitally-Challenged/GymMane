import { object } from "../src/protocol.js";
export type Transport = (url: string, init: RequestInit) => Promise<Response>;
export const transport: Transport = (url, init) =>
  fetch(url, {
    ...init,
    redirect: "error",
    signal: AbortSignal.timeout(10000),
  });
export class ProviderError extends Error {
  constructor(
    public status: number,
    public retryAt: Date,
  ) {
    super("Strava request failed");
  }
}
// Limits apply across the application, not individually to an athlete.
export function rateLimitUntil(response: Response, now = Date.now()): Date {
  let until = now;
  for (const prefix of ["x-ratelimit", "x-readratelimit"]) {
    const limits = (response.headers.get(`${prefix}-limit`) ?? "")
      .split(",")
      .map(Number);
    const usage = (response.headers.get(`${prefix}-usage`) ?? "")
      .split(",")
      .map(Number);
    if (limits.length !== 2 || usage.length !== 2) continue;
    if (limits[0] > 0 && usage[0] >= limits[0])
      until = Math.max(until, (Math.floor(now / 900000) + 1) * 900000 + 1000);
    if (limits[1] > 0 && usage[1] >= limits[1])
      until = Math.max(
        until,
        (Math.floor(now / 86400000) + 1) * 86400000 + 1000,
      );
  }
  if (response.status === 429) {
    const retry = response.headers.get("retry-after");
    const parsed =
      retry && /^\d+$/.test(retry)
        ? now + Number(retry) * 1000
        : Date.parse(retry ?? "");
    until = Math.max(
      until,
      Number.isFinite(parsed)
        ? parsed
        : (Math.floor(now / 900000) + 1) * 900000 + 1000,
    );
  }
  return new Date(until);
}
export function providerId(value: unknown): string | null {
  if (typeof value === "string" && /^[1-9]\d*$/.test(value)) return value;
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? String(value)
    : null;
}
export async function responseObject(
  response: Response,
): Promise<Record<string, unknown>> {
  const value: unknown = await response.json();
  if (!object(value)) throw new Error("Invalid provider response");
  return value;
}
