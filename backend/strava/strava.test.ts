// Retry cases share these hooks and fixtures; run serially within this file.
import "./retry-cases.js";
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { SyncStore } from "../src/store.js";
import { TokenCipher } from "./crypto.js";
import { strengthPayload, movementMap } from "./payload.js";
import { rateLimitUntil, type Transport } from "./transport.js";
import {
  key,
  fixture,
  json,
  tokens,
  dbUrl,
  integration,
  pool,
  moduleFor,
  account,
  connect,
  workout,
  enqueue,
  job,
  due,
} from "./test-support.js";

test("paused workouts retain actual start, elapsed and active time", () => {
  const p = strengthPayload({ ...fixture(), dur: 600 });
  assert.equal(p.start_time, "2026-10-20T17:00:00Z");
  assert.equal(p.elapsed_time, 1800);
  assert.equal(p.active_time, 600);
  for (const startedAt of [
    undefined,
    null,
    "2026-02-30T17:00:00Z",
    "2026-10-20T17:00:00",
    "2026-10-20T17:31:00Z",
    "2026-10-20T17:29:59Z",
  ]) {
    assert.throws(
      () => strengthPayload({ ...fixture(), startedAt }),
      /start|timing/i,
    );
  }
});

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
  assert.equal(p.start_time, "2026-10-20T17:00:00Z");
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
  "legacy start is unsupported and paused timing survives worker restart",
  async () => {
    const uploads: unknown[] = [];
    const fetch: Transport = async (url, init) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      const file = (init.body as FormData).get("file") as Blob;
      uploads.push(JSON.parse(await file.text()));
      return json({ id: 990, activity_id: 991 });
    };
    const a = await account(),
      m = moduleFor(fetch);
    await connect(m, a);
    const legacy = await workout(a);
    await pool.query(
      "UPDATE sync_entities SET payload=payload-'startedAt' WHERE entity_id=$1",
      [legacy],
    );
    await m.call("POST", "/v1/strava/export", a, {
      workoutId: legacy,
      revision: 1,
    });
    assert.equal((await job(legacy)).status, "unsupported");
    const paused = await workout(a);
    await pool.query(
      "UPDATE sync_entities SET payload=jsonb_set(payload,'{dur}','600') WHERE entity_id=$1",
      [paused],
    );
    await m.call("POST", "/v1/strava/export", a, {
      workoutId: paused,
      revision: 1,
    });
    await moduleFor(fetch).tick();
    assert.equal((await job(paused)).status, "confirmed");
    assert.equal(uploads.length, 1);
    assert.deepEqual(uploads[0], strengthPayload({ ...fixture(), dur: 600 }));
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

// Intercept only the worker connection; all SQL still runs against PostgreSQL.
function workerDatabase(
  hook: (sql: string, run: () => Promise<unknown>) => Promise<unknown>,
) {
  const database = new Pool({ connectionString: dbUrl });
  database.on("connect", (client) => {
    client.query = new Proxy(client.query, {
      apply(target, self, args) {
        return hook(String(args[0]), () => Reflect.apply(target, self, args));
      },
    });
  });
  return database;
}
async function mutateWorkout(
  a: string,
  id: string,
  deleted: boolean,
  database = pool,
) {
  const result = await new SyncStore(database).push(a, [
    {
      operationId: randomUUID(),
      entityType: "workout",
      entityId: id,
      baseRevision: 1,
      deleted,
      payload: deleted ? null : { ...fixture(), id, n: "Edited" },
    },
  ]);
  assert.equal(result.results[0].status, "accepted");
  assert.equal(result.results[0].entity.revision, 2);
}
for (const deleted of [false, true]) {
  integration(
    `SyncStore ${deleted ? "deletion" : "edit"} committed before intent prevents POST`,
    async () => {
      const a = await account();
      let uploads = 0;
      const fetch: Transport = async (url) => {
        if (url.endsWith("/oauth/token")) return json(tokens());
        uploads++;
        return json({ id: 902 });
      };
      const m = moduleFor(fetch);
      await connect(m, a);
      const id = await enqueue(m, a);
      let mutated = false;
      const database = workerDatabase(async (sql, run) => {
        // BEGIN is the fixed worker's boundary; SELECT covers the old worker.
        if (
          !mutated &&
          (sql === "BEGIN" || sql.startsWith("SELECT revision,deleted"))
        ) {
          mutated = true;
          await mutateWorkout(a, id, deleted);
        }
        return run();
      });
      try {
        await moduleFor(fetch, database).tick();
        assert(mutated);
        assert.equal(uploads, 0);
        assert.equal((await job(id)).status, "unsupported");
        assert.equal((await job(id)).attempts, 0);
      } finally {
        await database.end();
      }
    },
  );
  integration(
    `SyncStore ${deleted ? "deletion" : "edit"} after validation waits for intent and cannot cancel it`,
    async () => {
      const a = await account();
      let mutation: Promise<void> | undefined;
      let entered!: () => void;
      const mutationStarted = new Promise<void>((resolve) => {
        entered = resolve;
      });
      const syncDatabase = workerDatabase(async (sql, run) => {
        const pending = run();
        if (sql.includes("FROM sync_accounts") && sql.endsWith("FOR UPDATE"))
          entered();
        return pending;
      });
      let uploads = 0;
      const fetch: Transport = async (url) => {
        if (url.endsWith("/oauth/token")) return json(tokens());
        assert.equal((await job(id)).status, "sending");
        // Sync can finish while the external request is in flight. Intent has
        // already committed, so the original revision may still be delivered.
        assert(mutation);
        await mutation;
        uploads++;
        return json({ id: 903, activity_id: 904 });
      };
      const m = moduleFor(fetch);
      await connect(m, a);
      const id = await enqueue(m, a);
      let checked = false;
      const database = workerDatabase(async (sql, run) => {
        const result = await run();
        if (sql.startsWith("SELECT revision,deleted")) {
          checked = true;
          // The exact old race boundary: source was read, intent not yet saved.
          // A separate session must be unable to take SyncStore's account lock.
          await assert.rejects(
            pool.query(
              "SELECT account_id FROM sync_accounts WHERE account_id=$1 FOR UPDATE NOWAIT",
              [a],
            ),
            { code: "55P03" },
          );
          mutation = mutateWorkout(a, id, deleted, syncDatabase);
          // Resume only once real SyncStore has issued its conflicting lock query.
          await mutationStarted;
        }
        return result;
      });
      try {
        await moduleFor(fetch, database).tick();
        assert(checked);
        assert.equal(uploads, 1);
        assert.equal((await job(id)).status, "confirmed");
        await m.tick();
        assert.equal(uploads, 1);
      } finally {
        await database.end();
        await mutation;
        await syncDatabase.end();
      }
    },
  );
}
