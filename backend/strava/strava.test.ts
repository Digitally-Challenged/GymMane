import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { Pool } from "pg";
import { migrate } from "../src/migrate.js";
import { RouteRegistry } from "../src/modules.js";
import { createStravaModule } from "./index.js";
import { TokenCipher } from "./crypto.js";
import { strengthPayload, movementMap } from "./payload.js";
import { rateLimitUntil, type Transport } from "./transport.js";
const key = randomBytes(32).toString("base64");
const env = {
  STRAVA_CLIENT_ID: "123",
  STRAVA_CLIENT_SECRET: "test-only",
  STRAVA_TOKEN_KEY: key,
  STRAVA_REDIRECT_URI: "https://example.test/v1/strava/callback",
};
const fixture = () => ({
  origin: "gymmane",
  d: "2026-10-20T17:30:00Z",
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
const json = (
  value: unknown,
  status = 200,
  headers: Record<string, string> = {},
) => new Response(JSON.stringify(value), { status, headers });
const tokens = (
  athlete = 42,
  expiry = Math.floor(Date.now() / 1000) + 3600,
) => ({
  access_token: "access",
  refresh_token: "refresh",
  expires_at: expiry,
  athlete: { id: athlete },
});
const dbUrl = process.env.TEST_DATABASE_URL;
const integration = dbUrl ? test : test.skip;
let pool: Pool;
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
function moduleFor(fetch: Transport) {
  const module = createStravaModule(pool, env, fetch),
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
async function account() {
  const id = randomUUID();
  await pool.query("INSERT INTO sync_accounts(account_id) VALUES($1)", [id]);
  return id;
}
async function connect(m: ReturnType<typeof moduleFor>, a: string) {
  const c = (await m.call("POST", "/v1/strava/connect", a)) as {
    authorizationUrl: string;
  };
  const state = new URL(c.authorizationUrl).searchParams.get("state");
  const path = `/v1/strava/callback?state=${state}&code=code&scope=activity:write`;
  await m.call("GET", path, "");
  return path;
}
async function workout(a: string) {
  const id = randomUUID();
  await pool.query(
    "INSERT INTO sync_entities(account_id,entity_type,entity_id,revision,deleted,payload,cursor) VALUES($1,'workout',$2,1,false,$3,0)",
    [a, id, { ...fixture(), id }],
  );
  return id;
}
async function enqueue(m: ReturnType<typeof moduleFor>, a: string) {
  const id = await workout(a);
  await m.call("POST", "/v1/strava/export", a, { workoutId: id, revision: 1 });
  return id;
}
async function job(id: string) {
  return (
    await pool.query("SELECT * FROM strava_jobs WHERE workout_id=$1", [id])
  ).rows[0];
}
async function due() {
  await pool.query(
    "UPDATE strava_jobs SET next_attempt=now()-interval '1 second'",
  );
}

test("AES-GCM protects tokens and binds ciphertext to account", () => {
  const c = new TokenCipher(key),
    t = tokens(),
    v = c.seal(t, "a");
  assert.deepEqual(c.open(v, "a"), t);
  assert.throws(() => c.open(v, "b"));
  assert.throws(() => c.open(v.slice(0, -3) + "abc", "a"));
  assert.throws(() => new TokenCipher("bad"));
  assert(!v.includes("refresh"));
});
test("documented strength JSON uses recorded duration, kg and no invented metrics", () => {
  const p = strengthPayload(fixture());
  assert.equal(p.version, "1.0");
  assert.equal(p.start_time, "2026-10-20T17:00:00.000Z");
  assert.equal(p.elapsed_time, 1800);
  assert.equal(p.utc_offset, -18000);
  assert.deepEqual(p.sets[0], {
    exercise_type: "MACHINE_CHEST_PRESS",
    repetitions: 8,
    weight: 40,
  });
  assert(!("total_calories" in p));
  assert(!("start_time" in p.sets[0]));
  assert.equal(movementMap.get("EIeI8Vf"), "BARBELL_BENCH_PRESS");
  for (const delta of [
    { origin: "import" },
    { origin: "unknown" },
    { d: "2026-10-20T17:30:00" },
    { dur: 0 },
    { utcOffsetSeconds: undefined },
    { ex: [{ id: "unknown", s: [{ r: 8, w: 10 }] }] },
  ])
    assert.throws(() => strengthPayload({ ...fixture(), ...delta }));
});
test("rate limits honor daily, quarter-hour and Retry-After gates", () => {
  const now = Date.parse("2026-10-20T12:01:00Z");
  assert.equal(
    rateLimitUntil(
      json({}, 200, {
        "x-ratelimit-limit": "200,2000",
        "x-ratelimit-usage": "10,2000",
      }),
      now,
    ).toISOString(),
    "2026-10-21T00:00:01.000Z",
  );
  assert.equal(
    rateLimitUntil(json({}, 429), now).toISOString(),
    "2026-10-20T12:15:01.000Z",
  );
  assert.equal(
    rateLimitUntil(json({}, 429, { "retry-after": "60" }), now).getTime(),
    now + 60000,
  );
});
integration(
  "OAuth state is expiring, single-use and bound to its account",
  async () => {
    let calls = 0;
    const m = moduleFor(async () => {
      calls++;
      return json(tokens());
    });
    const a = await account(),
      b = await account();
    const callback = await connect(m, a);
    await assert.rejects(m.call("GET", callback, b), /expired or already used/);
    assert.equal(calls, 1);
    const status = (await m.call("GET", "/v1/strava/status", b)) as {
      connected: boolean;
    };
    assert.equal(status.connected, false);
    const start = (await m.call("POST", "/v1/strava/connect", b)) as {
      authorizationUrl: string;
    };
    await pool.query(
      "UPDATE strava_states SET expires_at=now()-interval '1 second'",
    );
    await assert.rejects(
      m.call(
        "GET",
        `/v1/strava/callback?state=${new URL(start.authorizationUrl).searchParams.get("state")}&code=x&scope=activity:write`,
        a,
      ),
      /expired/,
    );
    assert.equal(calls, 1);
  },
);
integration(
  "exports load owned persisted revision and ignore no arbitrary payload",
  async () => {
    const m = moduleFor(async () => json(tokens()));
    const a = await account(),
      b = await account();
    await connect(m, a);
    const id = await workout(a);
    await assert.rejects(
      m.call("POST", "/v1/strava/export", b, { workoutId: id, revision: 1 }),
      /not found/,
    );
    await assert.rejects(
      m.call("POST", "/v1/strava/export", a, { workoutId: id, revision: 2 }),
      /latest/,
    );
    await assert.rejects(
      m.call("POST", "/v1/strava/export", a, {
        workoutId: id,
        revision: 1,
        payload: fixture(),
      }),
      /Invalid/,
    );
    const first = await m.call("POST", "/v1/strava/export", a, {
      workoutId: id,
      revision: 1,
    });
    assert.deepEqual(
      await m.call("POST", "/v1/strava/export", a, {
        workoutId: id,
        revision: 1,
      }),
      first,
    );
    assert.equal((await job(id)).payload.sets[0].weight, 40);
  },
);
integration(
  "refresh is serialized across replicas and latest token persists atomically",
  async () => {
    let refreshes = 0,
      uploads = 0;
    const fetch: Transport = async (url, init) => {
      if (url.endsWith("/oauth/token")) {
        const body = init.body as URLSearchParams;
        if (body.get("grant_type") === "refresh_token") {
          refreshes++;
          assert.equal(body.get("refresh_token"), "refresh");
          return json({ ...tokens(), refresh_token: "rotated" });
        }
        return json(tokens(42, 1));
      }
      uploads++;
      return json({ id: uploads, activity_id: 100 + uploads });
    };
    const a = await account(),
      m = moduleFor(fetch),
      replica = moduleFor(fetch);
    await connect(m, a);
    await enqueue(m, a);
    await enqueue(m, a);
    await Promise.all([m.tick(), replica.tick()]);
    await m.tick();
    assert.equal(refreshes, 1);
    assert.equal(uploads, 2);
    const c = (
      await pool.query("SELECT * FROM strava_connections WHERE account_id=$1", [
        a,
      ])
    ).rows[0];
    assert.equal(
      new TokenCipher(key).open(c.tokens, a).refresh_token,
      "rotated",
    );
  },
);
integration(
  "lost POST response stays unknown across retry, edit and restart",
  async () => {
    let uploads = 0;
    const fetch: Transport = async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      uploads++;
      throw new Error("response lost after acceptance");
    };
    const a = await account(),
      m = moduleFor(fetch);
    await connect(m, a);
    const id = await enqueue(m, a);
    await m.tick();
    assert.equal((await job(id)).status, "unknown");
    await moduleFor(fetch).tick();
    await m.call("POST", "/v1/strava/export", a, {
      workoutId: id,
      revision: 1,
    });
    await pool.query("UPDATE sync_entities SET revision=2 WHERE entity_id=$1", [
      id,
    ]);
    const edit = (await m.call("POST", "/v1/strava/export", a, {
      workoutId: id,
      revision: 2,
    })) as { status: string };
    assert.equal(edit.status, "unsupported");
    assert.equal(uploads, 1);
  },
);
integration(
  "accepted upload identifier survives polling failures and restart",
  async () => {
    let uploads = 0,
      polls = 0;
    const fetch: Transport = async (url, init) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      if (init.method === "POST") {
        uploads++;
        const form = init.body as FormData;
        assert.equal(form.get("data_type"), "json");
        assert.equal(form.get("sport_type"), "WeightTraining");
        const file = form.get("file") as Blob;
        assert.equal(JSON.parse(await file.text()).sets.length, 2);
        return json({ id_str: "9007199254740998" });
      }
      polls++;
      assert(url.endsWith("/9007199254740998"));
      if (polls === 1) throw new Error("timeout");
      return json({ id_str: "9007199254740998", activity_id: 123 });
    };
    const a = await account(),
      m = moduleFor(fetch);
    await connect(m, a);
    const id = await enqueue(m, a);
    await m.tick();
    assert.equal((await job(id)).status, "processing");
    await due();
    await moduleFor(fetch).tick();
    assert.equal((await job(id)).upload_id, "9007199254740998");
    await due();
    await moduleFor(fetch).tick();
    assert.equal((await job(id)).status, "confirmed");
    assert.equal(uploads, 1);
  },
);
integration(
  "429 retries only after durable application gate; 5xx POST never retries",
  async () => {
    let uploads = 0;
    const fetch: Transport = async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      uploads++;
      return uploads === 1
        ? json({}, 429, { "retry-after": "60" })
        : json({}, 503);
    };
    const a = await account(),
      m = moduleFor(fetch);
    await connect(m, a);
    const id = await enqueue(m, a);
    await m.tick();
    assert.equal((await job(id)).status, "queued");
    await due();
    await m.tick();
    assert.equal(uploads, 1);
    await pool.query("UPDATE strava_throttle SET until_at='-infinity'");
    await due();
    await m.tick();
    assert.equal((await job(id)).status, "unknown");
    await due();
    await m.tick();
    assert.equal(uploads, 2);
  },
);
integration(
  "crashed sending jobs never resend; refresh intent loss requires reconnect",
  async () => {
    let requests = 0;
    const m = moduleFor(async () => {
      requests++;
      return json(tokens());
    });
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    await pool.query(
      "UPDATE strava_jobs SET status='sending' WHERE workout_id=$1",
      [id],
    );
    await m.tick();
    assert.equal((await job(id)).status, "unknown");
    const id2 = await enqueue(m, a);
    await pool.query(
      "UPDATE strava_connections SET refresh_pending=true WHERE account_id=$1",
      [a],
    );
    await m.tick();
    assert.equal((await job(id2)).status, "needsAuthorization");
    assert.equal(requests, 1);
  },
);
integration(
  "disconnect fences jobs and pending OAuth states; reports uncertain revocation",
  async () => {
    let requests = 0;
    const m = moduleFor(async (url) => {
      requests++;
      if (url.endsWith("/oauth/token")) return json(tokens());
      throw new Error("offline");
    });
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    const start = (await m.call("POST", "/v1/strava/connect", a)) as {
      authorizationUrl: string;
    };
    assert.deepEqual(await m.call("POST", "/v1/strava/disconnect", a), {
      connected: false,
      revocationStatus: "unconfirmed",
    });
    await m.tick();
    assert.equal((await job(id)).status, "needsAuthorization");
    await assert.rejects(
      m.call(
        "GET",
        `/v1/strava/callback?state=${new URL(start.authorizationUrl).searchParams.get("state")}&code=x&scope=activity:write`,
        a,
      ),
    );
    assert.equal(requests, 2);
    const c = (
      await pool.query("SELECT * FROM strava_connections WHERE account_id=$1", [
        a,
      ])
    ).rows[0];
    assert.equal(c.tokens, null);
  },
);
integration(
  "deleted source and revoked provider stop delivery; polling retry bound preserves ID",
  async () => {
    const m = moduleFor(async (url) =>
      url.endsWith("/oauth/token") ? json(tokens()) : json({}, 401),
    );
    const a = await account();
    await connect(m, a);
    const deleted = await enqueue(m, a);
    await pool.query(
      "UPDATE sync_entities SET deleted=true,payload=NULL WHERE entity_id=$1",
      [deleted],
    );
    await m.tick();
    assert.equal((await job(deleted)).status, "unsupported");
    const revoked = await enqueue(m, a);
    await m.tick();
    assert.equal((await job(revoked)).status, "needsAuthorization");
    await pool.query(
      "UPDATE strava_jobs SET status='processing',upload_id='123',attempts=30 WHERE workout_id=$1",
      [revoked],
    );
    await due();
    await m.tick();
    assert.equal((await job(revoked)).status, "unknown");
    assert.equal((await job(revoked)).upload_id, "123");
  },
);
integration(
  "disconnect waits for in-flight submission then fences other queued jobs",
  async () => {
    let release!: () => void, entered!: () => void;
    const started = new Promise<void>((r) => (entered = r)),
      gate = new Promise<void>((r) => (release = r));
    let uploads = 0;
    const m = moduleFor(async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      if (url.endsWith("/oauth/deauthorize")) return json({});
      uploads++;
      entered();
      await gate;
      return json({ id: 901 });
    });
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a),
      id2 = await enqueue(m, a);
    const tick = m.tick();
    await started;
    const disconnect = m.call("POST", "/v1/strava/disconnect", a);
    release();
    await Promise.all([tick, disconnect]);
    await m.tick();
    assert.equal(uploads, 1);
    assert.equal((await job(id)).upload_id, "901");
    assert.equal((await job(id)).status, "needsAuthorization");
    assert.equal((await job(id2)).status, "needsAuthorization");
  },
);
integration(
  "lost refresh response cannot rotate twice and permission denial consumes state",
  async () => {
    let refreshes = 0;
    const m = moduleFor(async (_url, init) => {
      const body = init.body as URLSearchParams;
      if (body.get("grant_type") === "refresh_token") {
        refreshes++;
        throw new Error("rotated but response lost");
      }
      return json(tokens(42, 1));
    });
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    await m.tick();
    await m.tick();
    assert.equal(refreshes, 1);
    assert.equal((await job(id)).status, "needsAuthorization");
    const start = (await m.call("POST", "/v1/strava/connect", a)) as {
      authorizationUrl: string;
    };
    const state = new URL(start.authorizationUrl).searchParams.get("state");
    const callback = `/v1/strava/callback?state=${state}&code=x&scope=read`;
    await assert.rejects(m.call("GET", callback, a), /activity:write/);
    await assert.rejects(m.call("GET", callback, a), /already used/);
  },
);
integration(
  "unknown and invalid provider success never claim delivery",
  async () => {
    let uploads = 0;
    const m = moduleFor(async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      uploads++;
      return json({ status: "processing" });
    });
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    await m.tick();
    assert.equal((await job(id)).status, "unknown");
    await m.tick();
    assert.equal(uploads, 1);
  },
);
