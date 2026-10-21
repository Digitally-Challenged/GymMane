import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { SyncStore } from "../src/store.js";
import type { Transport } from "./transport.js";
import {
  account,
  fixture,
  workout,
  connect,
  due,
  enqueue,
  integration,
  json,
  moduleFor,
  pool,
  tokens,
} from "./test-support.js";

integration(
  "unsent auth failure requires same-athlete reconnect and explicit idempotent retry",
  async () => {
    let refreshFails = true;
    let uploads = 0;
    const fetch: Transport = async (url, init) => {
      if (url.endsWith("/oauth/token")) {
        if (
          (init.body as URLSearchParams).get("grant_type") === "refresh_token"
        )
          return json({}, 401);
        return json(tokens(42, refreshFails ? 1 : undefined));
      }
      uploads++;
      return json({ id: 900, activity_id: 901 });
    };
    const m = moduleFor(fetch);
    const a = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    const body = { workoutId: id, revision: 1 };
    await m.tick();
    const status = async () =>
      (await m.call("GET", "/v1/strava/status", a)) as {
        jobs: { name: string; canRetry: boolean; status: string }[];
      };
    assert.equal((await status()).jobs[0].status, "needsAuthorization");
    assert.equal((await status()).jobs[0].canRetry, false);
    refreshFails = false;
    await connect(m, a);
    assert.equal((await status()).jobs[0].name, "Strength");
    assert.equal((await status()).jobs[0].canRetry, true);
    await due();
    await m.tick();
    assert.equal(uploads, 0);
    const [retried, replay] = await Promise.all([
      m.call("POST", "/v1/strava/retry", a, body),
      moduleFor(fetch).call("POST", "/v1/strava/retry", a, body),
    ]);
    assert.equal((retried as { status: string }).status, "queued");
    assert.deepEqual(replay, retried);
    await Promise.all([m.tick(), moduleFor(fetch).tick()]);
    assert.equal(uploads, 1);
    assert.equal((await status()).jobs[0].status, "confirmed");
    assert.equal((await status()).jobs[0].canRetry, false);
  },
);

integration("local provider throttle does not record POST intent", async () => {
  let uploads = 0;
  let expired = true;
  const m = moduleFor(async (url, init) => {
    if (url.endsWith("/oauth/token")) {
      if ((init.body as URLSearchParams).get("grant_type") === "refresh_token")
        return json(tokens(), 200, {
          "x-ratelimit-limit": "200,2000",
          "x-ratelimit-usage": "200,1",
        });
      return json(tokens(42, expired ? 1 : undefined));
    }
    uploads++;
    return json({ id: 910 });
  });
  const a = await account();
  await connect(m, a);
  const id = await enqueue(m, a);
  await m.tick();
  assert.equal(uploads, 0);
  await pool.query("UPDATE strava_throttle SET until_at='-infinity'");
  expired = false;
  await connect(m, a);
  const status = await statusJob(m, a);
  assert.equal(status.canRetry, true);
  await m.call("POST", "/v1/strava/retry", a, { workoutId: id, revision: 1 });
  await m.tick();
  assert.equal(uploads, 1);
});

async function statusJob(m: ReturnType<typeof moduleFor>, a: string) {
  return (
    (await m.call("GET", "/v1/strava/status", a)) as {
      jobs: { status: string; canRetry: boolean; name: string }[];
    }
  ).jobs[0];
}

for (const outcome of [
  "responseLost",
  "invalidSuccess",
  "unauthorized",
  "processing",
  "confirmed",
] as const) {
  integration(
    `${outcome} submission cannot be retried after reconnect`,
    async () => {
      let uploads = 0;
      const m = moduleFor(async (url) => {
        if (url.endsWith("/oauth/token")) return json(tokens());
        uploads++;
        if (outcome === "responseLost")
          throw new Error("accepted but response lost");
        if (outcome === "invalidSuccess") return json({ status: "accepted" });
        if (outcome === "unauthorized") return json({}, 401);
        return json(
          outcome === "processing"
            ? { id: 920 }
            : { id: 920, activity_id: 921 },
        );
      });
      const a = await account();
      await connect(m, a);
      const id = await enqueue(m, a);
      const body = { workoutId: id, revision: 1 };
      await m.tick();
      await connect(m, a);
      assert.equal((await statusJob(m, a)).canRetry, false);
      await assert.rejects(m.call("POST", "/v1/strava/retry", a, body), {
        status: 409,
      });
      await due();
      await m.tick();
      assert.equal(uploads, 1);
    },
  );
}

integration(
  "another account or athlete cannot retry an unsent job",
  async () => {
    let athlete = 42;
    let uploads = 0;
    const m = moduleFor(async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens(athlete));
      if (url.endsWith("/oauth/deauthorize")) return json({});
      uploads++;
      return json({ id: 930 });
    });
    const a = await account();
    const b = await account();
    await connect(m, a);
    const id = await enqueue(m, a);
    const body = { workoutId: id, revision: 1 };
    await m.call("POST", "/v1/strava/disconnect", a);
    athlete = 43;
    await connect(m, b);
    await assert.rejects(m.call("POST", "/v1/strava/retry", b, body), {
      status: 404,
    });
    // Releasing athlete 43 from account B still does not transfer A's old job.
    await m.call("POST", "/v1/strava/disconnect", b);
    await connect(m, a);
    assert.equal((await statusJob(m, a)).canRetry, false);
    await assert.rejects(m.call("POST", "/v1/strava/retry", a, body), {
      status: 409,
    });
    await due();
    await m.tick();
    assert.equal(uploads, 0);
    // The recorded athlete survives disconnect and allows only the original owner.
    await m.call("POST", "/v1/strava/disconnect", a);
    athlete = 42;
    await connect(m, a);
    assert.equal((await statusJob(m, a)).canRetry, true);
    await m.call("POST", "/v1/strava/retry", a, body);
    await m.tick();
    assert.equal(uploads, 1);
  },
);

for (const deleted of [false, true]) {
  integration(
    `retry rejects ${deleted ? "deleted" : "edited"} source revision`,
    async () => {
      let uploads = 0;
      const m = moduleFor(async (url) => {
        if (url.endsWith("/oauth/token")) return json(tokens());
        uploads++;
        return json({ id: 940 });
      });
      const a = await account();
      await connect(m, a);
      const id = await enqueue(m, a);
      await connect(m, a);
      assert.equal((await statusJob(m, a)).canRetry, true);
      const changed = await new SyncStore(pool).push(a, [
        {
          operationId: randomUUID(),
          entityType: "workout",
          entityId: id,
          baseRevision: 1,
          deleted,
          payload: deleted ? null : { ...fixture(), id, n: "Edited" },
        },
      ]);
      assert.equal(changed.results[0].status, "accepted");
      assert.equal((await statusJob(m, a)).canRetry, false);
      await assert.rejects(
        m.call("POST", "/v1/strava/retry", a, {
          workoutId: id,
          revision: 1,
        }),
        { status: 409 },
      );
      await due();
      await m.tick();
      assert.equal(uploads, 0);
    },
  );
}

integration(
  "retry rejects invalid references and unsupported sources",
  async () => {
    let uploads = 0;
    const m = moduleFor(async (url) => {
      if (url.endsWith("/oauth/token")) return json(tokens());
      uploads++;
      return json({ id: 950 });
    });
    const a = await account();
    await connect(m, a);
    const id = await workout(a);
    await pool.query(
      "UPDATE sync_entities SET payload=payload-'startedAt' WHERE entity_id=$1",
      [id],
    );
    const body = { workoutId: id, revision: 1 };
    await m.call("POST", "/v1/strava/export", a, body);
    assert.equal((await statusJob(m, a)).canRetry, false);
    await assert.rejects(m.call("POST", "/v1/strava/retry", a, body), {
      status: 409,
    });
    for (const invalid of [
      null,
      {},
      { ...body, revision: 0 },
      { ...body, revision: 1.5 },
      { ...body, workoutId: "invalid" },
      { ...body, payload: {} },
    ])
      await assert.rejects(m.call("POST", "/v1/strava/retry", a, invalid), {
        status: 400,
      });
    await m.tick();
    assert.equal(uploads, 0);
  },
);

integration(
  "retry migration never invents athlete ownership or erases legacy intent",
  async () => {
    const db = await pool.connect();
    try {
      await db.query("BEGIN");
      // Temporary legacy tables exercise the actual additive migration without
      // altering the shared integration schema or migration journal.
      await db.query(`CREATE TEMP TABLE strava_connections (
      account_id uuid, generation bigint, athlete_id text
    ) ON COMMIT DROP`);
      await db.query(`CREATE TEMP TABLE strava_jobs (
      label text, account_id uuid, generation bigint, status text,
      attempts integer, upload_id text, activity_id text,
      created_at timestamptz DEFAULT now()
    ) ON COMMIT DROP`);
      const a = randomUUID();
      await db.query("INSERT INTO strava_connections VALUES($1,2,'42')", [a]);
      await db.query(
        `INSERT INTO strava_jobs(label,account_id,generation,status,attempts,upload_id,activity_id)
      VALUES ('unsent',$1,2,'needsAuthorization',0,NULL,NULL),
             ('oldAthlete',$1,1,'needsAuthorization',0,NULL,NULL),
             ('attempted',$1,2,'needsAuthorization',1,NULL,NULL),
             ('interrupted',$1,2,'sending',0,NULL,NULL),
             ('knownUpload',$1,2,'failed',0,'999',NULL)`,
        [a],
      );
      await db.query(
        await readFile(
          new URL("../migrations/003_strava_retry.sql", import.meta.url),
          "utf8",
        ),
      );
      const { rows } = await db.query(
        "SELECT label,athlete_id,post_intent_at IS NOT NULL AS intent FROM strava_jobs ORDER BY label",
      );
      assert.deepEqual(rows, [
        { label: "attempted", athlete_id: "42", intent: true },
        { label: "interrupted", athlete_id: "42", intent: true },
        { label: "knownUpload", athlete_id: "42", intent: true },
        { label: "oldAthlete", athlete_id: null, intent: false },
        { label: "unsent", athlete_id: "42", intent: false },
      ]);
    } finally {
      await db.query("ROLLBACK");
      db.release();
    }
  },
);
