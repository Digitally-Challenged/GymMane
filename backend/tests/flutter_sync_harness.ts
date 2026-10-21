// Run through scripts/test-postgres.sh node --import tsx tests/flutter_sync_harness.ts.
// Signing material stays in memory; only short-lived JWTs enter the child environment.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { Pool } from "pg";
import { migrate } from "../src/migrate.js";
import { createApp } from "../src/server.js";

const databaseUrl = process.env.TEST_DATABASE_URL;
assert(databaseUrl, "Run with the disposable Postgres script");
const url = new URL(databaseUrl);
assert(
  ["localhost", "127.0.0.1"].includes(url.hostname) &&
    url.pathname.endsWith("_test"),
);
const pool = new Pool({ connectionString: databaseUrl });
const servers: Server[] = [];
async function listen(server: Server) {
  servers.push(server);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const address = server.address();
  assert(address && typeof address !== "string");
  return `http://127.0.0.1:${address.port}`;
}
try {
  await migrate(pool);
  const keys = await generateKeyPair("ES256");
  const publicKey = {
    ...(await exportJWK(keys.publicKey)),
    kid: "local-test",
    alg: "ES256",
  };
  const issuer = await listen(
    createServer((_request, response) => {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ keys: [publicKey] }));
    }),
  );
  const base = await listen(
    createApp(pool, {
      issuer,
      audience: "authenticated",
      jwksUrl: `${issuer}/jwks`,
    }),
  );
  const accounts = [randomUUID(), randomUUID()];
  const tokens = await Promise.all(
    accounts.map((account) =>
      new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: "local-test" })
        .setSubject(account)
        .setIssuer(issuer)
        .setAudience("authenticated")
        .setIssuedAt()
        .setExpirationTime("10m")
        .sign(keys.privateKey),
    ),
  );
  const child = spawn(
    "flutter",
    ["test", "test/sync/live_backend_test.dart", "--reporter", "expanded"],
    {
      cwd: new URL("../../", import.meta.url),
      stdio: "inherit",
      env: {
        ...process.env,
        GYMMANE_TEST_URL: base,
        GYMMANE_TEST_ACCOUNT: accounts[0],
        GYMMANE_TEST_TOKEN: tokens[0],
        GYMMANE_TEST_OTHER_ACCOUNT: accounts[1],
        GYMMANE_TEST_OTHER_TOKEN: tokens[1],
      },
    },
  );
  const timer = setTimeout(() => child.kill("SIGTERM"), 180_000);
  try {
    const [code] = await once(child, "exit");
    assert.equal(code, 0, "Flutter real-backend acceptance failed");
  } finally {
    clearTimeout(timer);
  }
} finally {
  for (const server of servers.reverse()) {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
  await pool.end();
}
