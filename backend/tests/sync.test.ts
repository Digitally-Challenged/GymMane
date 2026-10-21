import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createServer, type Server } from "node:http";
import { once } from "node:events";
import { Pool } from "pg";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { migrate } from "../src/migrate.js";
import { createApp } from "../src/server.js";
import { parsePush, parsePull } from "../src/protocol.js";

const databaseUrl = process.env.TEST_DATABASE_URL;
const integration = databaseUrl ? test : test.skip;
let pool: Pool, app: Server, jwks: Server, base: string, issuer: string;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
async function listen(server: Server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  return `http://127.0.0.1:${address.port}`;
}
async function token(
  account: string,
  overrides: { aud?: string; exp?: number; iat?: number } = {},
) {
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: "test" })
    .setSubject(account)
    .setIssuer(issuer)
    .setAudience(overrides.aud ?? "authenticated")
    .setIssuedAt(overrides.iat ?? Math.floor(Date.now() / 1000))
    .setExpirationTime(overrides.exp ?? Math.floor(Date.now() / 1000) + 300)
    .sign(keys.privateKey);
}
function operation(id = randomUUID(), revision = 0) {
  return {
    operationId: randomUUID(),
    entityType: "workout",
    entityId: id,
    baseRevision: revision,
    deleted: false,
    payload: { id, d: "2026-10-20T12:00:00Z", dur: 60, ex: [], n: "Test" },
  };
}
async function call(path: string, jwt: string, body?: unknown) {
  const response = await fetch(base + path, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      authorization: `Bearer ${jwt}`,
      "content-type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, body: (await response.json()) as any };
}
async function push(jwt: string, operations: unknown[]) {
  return call("/v1/sync/push", jwt, { schemaVersion: 1, operations });
}
before(async () => {
  if (!databaseUrl) return;
  const url = new URL(databaseUrl);
  assert(
    ["localhost", "127.0.0.1"].includes(url.hostname) &&
      url.pathname.endsWith("_test"),
    "Tests require a localhost database ending _test",
  );
  pool = new Pool({ connectionString: databaseUrl });
  await migrate(pool);
  await migrate(pool);
  keys = await generateKeyPair("ES256");
  const publicKey = {
    ...(await exportJWK(keys.publicKey)),
    kid: "test",
    alg: "ES256",
  };
  jwks = createServer((_req, res) => {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ keys: [publicKey] }));
  });
  issuer = await listen(jwks);
  app = createApp(pool, {
    issuer,
    audience: "authenticated",
    jwksUrl: issuer + "/.well-known/jwks.json",
  });
  base = await listen(app);
});
after(async () => {
  for (const server of [app, jwks])
    if (server)
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
  if (pool) await pool.end();
});
test("validation rejects invalid envelopes, payloads, and cursor bounds", () => {
  assert.throws(() => parsePush({ schemaVersion: 2, operations: [] }));
  assert.throws(() =>
    parsePush({
      schemaVersion: 1,
      operations: [{ ...operation(), payload: {} }],
    }),
  );
  assert.throws(() => parsePull(new URL("http://localhost/?cursor=-1")));
  assert.throws(() =>
    parsePull(new URL("http://localhost/?cursor=9223372036854775808")),
  );
  assert.throws(() => parsePull(new URL("http://localhost/?limit=101")));
  assert.throws(() =>
    parsePush({
      schemaVersion: 1,
      operations: Array.from({ length: 101 }, () => operation()),
    }),
  );
  const op = operation();
  (op.payload as any).legacy = { preserved: true };
  assert.deepEqual(
    parsePush({ schemaVersion: 1, operations: [op] })[0].payload,
    op.payload,
  );
});
integration(
  "real JWT signature, audience, expiry, revocation and account disable checks",
  async () => {
    const account = randomUUID(),
      jwt = await token(account);
    assert.equal((await call("/v1/sync/pull", "garbage")).status, 401);
    assert.equal(
      (await call("/v1/sync/pull", await token(account, { aud: "wrong" })))
        .status,
      401,
    );
    assert.equal(
      (await call("/v1/sync/pull", await token(account, { exp: 1 }))).status,
      401,
    );
    assert.equal((await call("/v1/sync/pull", jwt)).status, 200);
    await pool.query(
      "INSERT INTO sync_accounts(account_id,tokens_valid_after) VALUES($1,$2)",
      [account, Math.floor(Date.now() / 1000)],
    );
    assert.equal((await call("/v1/sync/pull", jwt)).status, 401);
    await pool.query(
      "UPDATE sync_accounts SET disabled=true WHERE account_id=$1",
      [account],
    );
    assert.equal((await call("/v1/sync/pull", jwt)).status, 403);
  },
);
integration(
  "idempotent accepted and conflict receipts, misuse, account isolation and immutable pagination",
  async () => {
    const a = await token(randomUUID()),
      b = await token(randomUUID()),
      op = operation();
    const first = await push(a, [op]);
    assert.equal(first.status, 200);
    assert.deepEqual((await push(a, [op])).body, first.body);
    assert.equal(
      (await push(a, [{ ...op, payload: { ...op.payload, n: "changed" } }]))
        .status,
      409,
    );
    assert.equal((await call("/v1/sync/pull", b)).body.entities.length, 0);
    assert.equal((await push(b, [op])).body.results[0].status, "accepted");
    const edit = operation(op.entityId, 1);
    assert.equal((await push(a, [edit])).body.results[0].entity.revision, 2);
    const conflict = operation(op.entityId, 1);
    const lost = await push(a, [conflict]);
    assert.equal(lost.body.results[0].status, "conflict");
    const tombstone = {
      ...operation(op.entityId, 2),
      deleted: true,
      payload: null,
    };
    assert.equal(
      (await push(a, [tombstone])).body.results[0].entity.deleted,
      true,
    );
    assert.deepEqual((await push(a, [conflict])).body, lost.body);
    let cursor = "0";
    const revisions: number[] = [];
    for (;;) {
      const page = (await call(`/v1/sync/pull?cursor=${cursor}&limit=1`, a))
        .body;
      revisions.push(...page.entities.map((e: any) => e.revision));
      cursor = page.nextCursor;
      if (!page.hasMore) break;
    }
    assert.deepEqual(revisions, [1, 2, 3]);
    assert.equal(
      (await call(`/v1/sync/pull?cursor=${cursor}`, a)).body.entities.length,
      0,
    );
  },
);
integration(
  "concurrent same-account creates serialize without cursor gaps or lost conflict",
  async () => {
    const jwt = await token(randomUUID()),
      id = randomUUID();
    const responses = await Promise.all(
      Array.from({ length: 8 }, () => push(jwt, [operation(id)])),
    );
    assert.equal(
      responses.filter((r) => r.body.results[0].status === "accepted").length,
      1,
    );
    assert.equal(
      responses.filter((r) => r.body.results[0].status === "conflict").length,
      7,
    );
    const page = (await call("/v1/sync/pull", jwt)).body;
    assert.equal(page.entities.length, 1);
    assert.equal(page.nextCursor, "1");
  },
);
integration(
  "SQL receipt failure rolls back entity, immutable change and cursor; retry succeeds",
  async () => {
    const account = randomUUID(),
      jwt = await token(account),
      op = operation();
    await pool.query(
      `CREATE OR REPLACE FUNCTION test_reject_receipt() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.account_id = '${account}'::uuid THEN RAISE EXCEPTION 'injected receipt failure'; END IF; RETURN NEW; END $$`,
    );
    await pool.query(
      "CREATE TRIGGER test_receipt_failure BEFORE INSERT ON sync_receipts FOR EACH ROW EXECUTE FUNCTION test_reject_receipt()",
    );
    try {
      assert.equal((await push(jwt, [op])).status, 503);
      for (const table of [
        "sync_entities",
        "sync_changes",
        "sync_receipts",
        "sync_accounts",
      ])
        assert.equal(
          (
            await pool.query(`SELECT 1 FROM ${table} WHERE account_id=$1`, [
              account,
            ])
          ).rowCount,
          0,
        );
    } finally {
      await pool.query("DROP TRIGGER test_receipt_failure ON sync_receipts");
      await pool.query("DROP FUNCTION test_reject_receipt()");
    }
    assert.equal((await push(jwt, [op])).body.results[0].entity.cursor, "1");
  },
);
integration(
  "malformed and oversized HTTP input, batch misuse atomic rollback, durable restart",
  async () => {
    const account = randomUUID(),
      jwt = await token(account),
      op = operation();
    assert.equal(
      (
        await push(
          jwt,
          Array.from({ length: 101 }, () => operation()),
        )
      ).status,
      413,
    );
    assert.equal(
      (
        await push(jwt, [
          { ...op, payload: { ...op.payload, n: "a".repeat(65536) } },
        ])
      ).status,
      413,
    );
    assert.equal((await push(jwt, [{ ...op, baseRevision: 5 }])).status, 400);
    assert.equal(
      (
        await push(jwt, [
          op,
          { ...op, payload: { ...op.payload, n: "misuse" } },
        ])
      ).status,
      409,
    );
    assert.equal((await call("/v1/sync/pull", jwt)).body.entities.length, 0);
    const accepted = await push(jwt, [op]);
    await new Promise<void>((resolve) => app.close(() => resolve()));
    app = createApp(pool, {
      issuer,
      audience: "authenticated",
      jwksUrl: issuer + "/.well-known/jwks.json",
    });
    base = await listen(app);
    assert.deepEqual((await push(jwt, [op])).body, accepted.body);
    assert.equal((await call("/v1/sync/pull", jwt)).body.nextCursor, "1");
  },
);

integration(
  "HTTP malformed JSON and invalid signed token are rejected",
  async () => {
    const jwt = await token(randomUUID());
    const malformed = await fetch(base + "/v1/sync/push", {
      method: "POST",
      headers: {
        authorization: `Bearer ${jwt}`,
        "content-type": "application/json",
      },
      body: "{",
    });
    assert.equal(malformed.status, 400);
    const parts = jwt.split(".");
    parts[2] = Buffer.alloc(64).toString("base64url");
    assert.equal((await call("/v1/sync/pull", parts.join("."))).status, 401);
    const oversized = await fetch(base + "/v1/sync/push", {
      method: "POST",
      headers: {
        authorization: `Bearer ${jwt}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ padding: "x".repeat(1024 * 1024) }),
    });
    assert.equal(oversized.status, 413);
  },
);

integration(
  "CORS uses exact allowlist and validates unauthenticated preflight",
  async () => {
    const server = createApp(
      pool,
      { issuer, audience: "authenticated", jwksUrl: issuer + "/jwks" },
      [],
      { allowedOrigins: ["https://app.example.test"] },
    );
    const address = await listen(server);
    try {
      const allowed = await fetch(address + "/v1/sync/push", {
        method: "OPTIONS",
        headers: {
          origin: "https://app.example.test",
          "access-control-request-method": "POST",
          "access-control-request-headers": "authorization,content-type",
        },
      });
      assert.equal(allowed.status, 204);
      assert.equal(
        allowed.headers.get("access-control-allow-origin"),
        "https://app.example.test",
      );
      const rejected = await fetch(address + "/v1/sync/pull", {
        headers: { origin: "https://evil.example.test" },
      });
      assert.equal(rejected.status, 403);
      assert.equal(rejected.headers.get("access-control-allow-origin"), null);
    } finally {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  },
);
