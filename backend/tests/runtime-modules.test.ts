import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { once } from "node:events";
import { createServer, type IncomingMessage, type Server } from "node:http";
import { test } from "node:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { Pool } from "pg";
import { migrate } from "../src/migrate.js";
import { RouteRegistry } from "../src/modules.js";
import { loadRuntimeModules } from "../src/runtime-modules.js";
import { createApp } from "../src/server.js";

const unavailable = {
  configured: false,
  connected: false,
  athleteId: null,
  status: "disconnected",
  jobs: [],
};
const configuredEnv = {
  STRAVA_ENABLED: "true",
  STRAVA_CLIENT_ID: "123",
  STRAVA_CLIENT_SECRET: "test-only",
  STRAVA_REDIRECT_URI: "https://example.test/v1/strava/callback",
  STRAVA_TOKEN_KEY: randomBytes(32).toString("base64"),
};
const mutations = ["connect", "disconnect", "export", "retry"];
async function registryFor(pool: Pool, env: NodeJS.ProcessEnv) {
  const modules = await loadRuntimeModules(pool, env);
  const registry = new RouteRegistry();
  modules.forEach((module) => module.register(registry, { pool }));
  return { modules, registry };
}
async function statusOf(registry: RouteRegistry, accountId = randomUUID()) {
  const handler = registry.get("GET", "/v1/strava/status");
  assert(handler, "disabled runtime must register GET /v1/strava/status");
  return handler({
    accountId,
    request: {} as IncomingMessage,
    url: new URL("https://example.test/v1/strava/status"),
    readJson: async () => assert.fail("status must not read a body"),
  });
}
async function listen(server: Server) {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  return `http://127.0.0.1:${address.port}`;
}
async function close(server: Server) {
  await new Promise<void>((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

test("disabled runtime exposes the unavailable Strava status", async () => {
  const pool = {} as Pool;
  const modules = await loadRuntimeModules(pool, { STRAVA_ENABLED: "false" });
  const registry = new RouteRegistry();
  modules.forEach((module) => module.register(registry, { pool }));
  const status = registry.get("GET", "/v1/strava/status");
  assert(status, "disabled runtime must register GET /v1/strava/status");
  assert.deepEqual(
    await status({
      accountId: "00000000-0000-4000-8000-000000000001",
      request: {} as IncomingMessage,
      url: new URL("https://example.test/v1/strava/status"),
      readJson: async () => assert.fail("status must not read a body"),
    }),
    {
      configured: false,
      connected: false,
      athleteId: null,
      status: "disconnected",
      jobs: [],
    },
  );
});

test("disabled flags ignore provider configuration and have no database or network effects", async (t) => {
  const network = t.mock.method(globalThis, "fetch", async () =>
    assert.fail("disabled Strava must not access the network"),
  );
  let databaseAccesses = 0;
  const pool = new Proxy({} as Pool, {
    get() {
      databaseAccesses++;
      assert.fail("disabled Strava must not access the database");
    },
  });
  for (const env of [
    {},
    { STRAVA_ENABLED: "false" },
    { ...configuredEnv, STRAVA_ENABLED: "false" },
    { STRAVA_ENABLED: "false", STRAVA_CLIENT_ID: "invalid-partial" },
    { ...configuredEnv, STRAVA_ENABLED: "TRUE" },
  ]) {
    const { modules, registry } = await registryFor(pool, env);
    assert.deepEqual(await statusOf(registry), unavailable);
    for (const module of modules) await module.tick();
    assert.deepEqual(await statusOf(registry), unavailable);
    for (const path of mutations)
      assert.equal(registry.get("POST", `/v1/strava/${path}`), undefined);
    assert.equal(registry.get("GET", "/v1/strava/callback"), undefined);
    assert.equal(
      registry.callbackVerifier("GET", "/v1/strava/status"),
      undefined,
    );
  }
  assert.equal(databaseAccesses, 0);
  assert.equal(network.mock.callCount(), 0);
});

test("disabled status enforces real JWT and account checks while mutation routes remain absent", async (t) => {
  const originalFetch = globalThis.fetch;
  let providerRequests = 0;
  t.mock.method(globalThis, "fetch", (...args: Parameters<typeof fetch>) => {
    const input = args[0];
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (url.hostname !== "127.0.0.1") {
      providerRequests++;
      assert.fail("disabled Strava must not contact a provider");
    }
    return originalFetch(...args);
  });
  const keys = await generateKeyPair("ES256");
  const publicKey = { ...(await exportJWK(keys.publicKey)), kid: "test" };
  const jwks = createServer((_request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ keys: [publicKey] }));
  });
  t.after(() => close(jwks));
  const issuer = await listen(jwks);
  const accountId = randomUUID();
  let disabled = false;
  let tokensValidAfter = 0;
  let authQueries = 0;
  const pool = {
    query: async (sql: string, parameters: string[]) => {
      assert.equal(
        sql,
        "SELECT disabled, tokens_valid_after FROM sync_accounts WHERE account_id=$1",
      );
      assert.deepEqual(parameters, [accountId]);
      authQueries++;
      return { rows: [{ disabled, tokens_valid_after: tokensValidAfter }] };
    },
    connect: async () => assert.fail("disabled Strava must not create jobs"),
  } as unknown as Pool;
  const modules = await loadRuntimeModules(pool, {
    ...configuredEnv,
    STRAVA_ENABLED: "false",
  });
  const app = createApp(
    pool,
    { issuer, audience: "authenticated", jwksUrl: issuer + "/jwks" },
    modules.map((module) => module.register),
  );
  t.after(() => close(app));
  const base = await listen(app);
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: "test" })
    .setSubject(accountId)
    .setIssuer(issuer)
    .setAudience("authenticated")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(keys.privateKey);
  const getStatus = (authorization?: string) =>
    fetch(base + "/v1/strava/status", {
      headers: authorization ? { authorization } : {},
    });
  assert.equal((await getStatus()).status, 401);
  assert.equal((await getStatus("Bearer invalid")).status, 401);
  assert.equal(authQueries, 0);
  const response = await getStatus(`Bearer ${jwt}`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), unavailable);
  disabled = true;
  assert.equal((await getStatus(`Bearer ${jwt}`)).status, 403);
  disabled = false;
  tokensValidAfter = Math.floor(Date.now() / 1000) + 1;
  assert.equal((await getStatus(`Bearer ${jwt}`)).status, 401);
  assert.equal(authQueries, 3);
  for (const authorization of [undefined, `Bearer ${jwt}`]) {
    const headers = authorization ? { authorization } : undefined;
    for (const path of mutations)
      assert.equal(
        (await fetch(`${base}/v1/strava/${path}`, { method: "POST", headers }))
          .status,
        404,
      );
    assert.equal(
      (await fetch(base + "/v1/strava/callback", { headers })).status,
      404,
    );
    assert.equal(
      (await fetch(base + "/v1/strava/status", { method: "POST", headers }))
        .status,
      404,
    );
  }
  for (const module of modules) await module.tick();
  assert.equal(authQueries, 3);
  assert.equal(providerRequests, 0);
});

test("enabled runtime with no provider configuration retains unavailable status and guarded routes", async () => {
  const { modules, registry } = await registryFor({} as Pool, {
    STRAVA_ENABLED: "true",
  });
  assert.deepEqual(await statusOf(registry), unavailable);
  const connect = registry.get("POST", "/v1/strava/connect");
  assert(connect);
  await assert.rejects(connect({} as never), { status: 503 });
  for (const module of modules) await module.tick();
});

test("enabled runtime still fails startup for incomplete provider configuration", async () => {
  await assert.rejects(
    loadRuntimeModules({} as Pool, {
      STRAVA_ENABLED: "true",
      STRAVA_CLIENT_ID: "123",
    }),
    /All Strava configuration values are required/,
  );
});

test("enabled runtime with valid configuration retains provider routes", async () => {
  const { registry } = await registryFor({} as Pool, configuredEnv);
  assert(registry.get("GET", "/v1/strava/status"));
  for (const path of mutations)
    assert(registry.get("POST", `/v1/strava/${path}`));
  assert(registry.get("GET", "/v1/strava/callback"));
  assert(registry.callbackVerifier("GET", "/v1/strava/callback"));
});

test(
  "enabled runtime reports configured status from PostgreSQL",
  {
    skip: !process.env.TEST_DATABASE_URL,
  },
  async (t) => {
    const url = new URL(process.env.TEST_DATABASE_URL!);
    assert(
      ["localhost", "127.0.0.1"].includes(url.hostname) &&
        url.pathname.endsWith("_test"),
    );
    const pool = new Pool({ connectionString: url.toString() });
    t.after(() => pool.end());
    await migrate(pool);
    const accountId = randomUUID();
    await pool.query("INSERT INTO sync_accounts(account_id) VALUES($1)", [
      accountId,
    ]);
    const { registry } = await registryFor(pool, configuredEnv);
    assert.deepEqual(await statusOf(registry, accountId), {
      ...unavailable,
      configured: true,
    });
  },
);
