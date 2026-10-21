import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { Pool } from "pg";
import { migrate } from "../src/migrate.js";
import { RouteRegistry } from "../src/modules.js";
import { createStravaModule } from "./index.js";
import { TokenCipher } from "./crypto.js";
import type { Transport } from "./transport.js";
export const key = randomBytes(32).toString("base64");
const env = {
  STRAVA_CLIENT_ID: "123",
  STRAVA_CLIENT_SECRET: "test-only",
  STRAVA_TOKEN_KEY: key,
  STRAVA_REDIRECT_URI: "https://example.test/v1/strava/callback",
};
export const fixture = () => ({
  origin: "gymmane",
  d: "2026-10-20T17:30:00Z",
  startedAt: "2026-10-20T17:00:00Z",
  dur: 1800,
  utcOffsetSeconds: -18000,
  n: "Strength",
  ex: [
    {
      id: "arsenal-forge-x-wide-chest-press",
      n: "Press",
      p: "chest",
      s: [
        { r: 8, w: 40 },
        { r: 6, w: 45 },
      ],
    },
  ],
});
export const json = (
  value: unknown,
  status = 200,
  headers: Record<string, string> = {},
) => new Response(JSON.stringify(value), { status, headers });
export const tokens = (
  athlete = 42,
  expiry = Math.floor(Date.now() / 1000) + 3600,
) => ({
  access_token: "access",
  refresh_token: "refresh",
  expires_at: expiry,
  athlete: { id: athlete },
});
export const dbUrl = process.env.TEST_DATABASE_URL;
export const integration = dbUrl ? test : test.skip;
export let pool: Pool;
before(async () => {
  if (!dbUrl) return;
  const u = new URL(dbUrl);
  assert(
    ["localhost", "127.0.0.1"].includes(u.hostname) &&
      u.pathname.endsWith("_test"),
  );
  pool = new Pool({ connectionString: dbUrl });
  await migrate(pool);
});
beforeEach(async () => {
  if (!pool) return;
  await pool.query("DELETE FROM strava_jobs");
  await pool.query("DELETE FROM strava_states");
  await pool.query("DELETE FROM strava_connections");
  await pool.query("UPDATE strava_throttle SET until_at='-infinity'");
});
after(async () => {
  await pool?.end();
});
export function moduleFor(fetch: Transport, database = pool) {
  const module = createStravaModule(database, env, fetch),
    registry = new RouteRegistry();
  module.register(registry, { pool });
  const call = async (
    method: string,
    path: string,
    account: string,
    body: unknown = {},
  ) => {
    const url = new URL(path, "https://example.test");
    const handler = registry.get(method, url.pathname);
    assert(handler);
    const verifier = registry.callbackVerifier(method, url.pathname);
    const accountId = verifier
      ? await verifier({} as IncomingMessage, url)
      : account;
    return handler({
      accountId,
      url,
      request: {} as IncomingMessage,
      readJson: async () => body,
    });
  };
  return { ...module, call };
}
export async function account() {
  const id = randomUUID();
  await pool.query("INSERT INTO sync_accounts(account_id) VALUES($1)", [id]);
  return id;
}
export async function connect(m: ReturnType<typeof moduleFor>, a: string) {
  const c = (await m.call("POST", "/v1/strava/connect", a)) as {
    authorizationUrl: string;
  };
  const state = new URL(c.authorizationUrl).searchParams.get("state");
  const path = `/v1/strava/callback?state=${state}&code=code&scope=activity:write`;
  await m.call("GET", path, "");
  return path;
}
export async function workout(a: string) {
  const id = randomUUID();
  await pool.query(
    "INSERT INTO sync_entities(account_id,entity_type,entity_id,revision,deleted,payload,cursor) VALUES($1,'workout',$2,1,false,$3,0)",
    [a, id, { ...fixture(), id }],
  );
  return id;
}
export async function enqueue(m: ReturnType<typeof moduleFor>, a: string) {
  const id = await workout(a);
  await m.call("POST", "/v1/strava/export", a, { workoutId: id, revision: 1 });
  return id;
}
export async function job(id: string) {
  return (
    await pool.query("SELECT * FROM strava_jobs WHERE workout_id=$1", [id])
  ).rows[0];
}
export async function due() {
  await pool.query(
    "UPDATE strava_jobs SET next_attempt=now()-interval '1 second'",
  );
}
