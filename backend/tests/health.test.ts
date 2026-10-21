import assert from "node:assert/strict";
import { once } from "node:events";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import type { Pool } from "pg";
import { createApp } from "../src/server.js";

const release = "a".repeat(40);
const auth = {
  issuer: "https://auth.example.invalid",
  audience: "authenticated",
  jwksUrl: "https://auth.example.invalid/jwks",
};

async function withApp(
  query: () => Promise<unknown>,
  run: (base: string) => Promise<void>,
) {
  const app = createApp({ query } as unknown as Pool, auth, [], {
    release,
    allowedOrigins: ["https://app.example.invalid"],
  });
  app.listen(0, "127.0.0.1");
  await once(app, "listening");
  const address = app.address();
  assert(address && typeof address !== "string");
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) =>
      app.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

test("GET health needs no bearer token and returns only readiness and exact release", async () => {
  let queries = 0;
  await withApp(
    async () => {
      queries++;
      return { rows: [{ secret: "must never escape" }] };
    },
    async (base) => {
      for (const headers of [
        new Headers(),
        new Headers({ authorization: "Bearer invalid" }),
      ]) {
        const response = await fetch(`${base}/health`, { headers });
        assert.equal(response.status, 200);
        assert.equal(response.headers.get("cache-control"), "no-store");
        assert.deepEqual(await response.json(), { status: "ok", release });
      }
    },
  );
  assert.equal(queries, 2);
});

for (const reason of [
  "database offline",
  "backend_migrations does not exist",
]) {
  test(`health returns safe unavailable identity when ${reason}`, async () => {
    await withApp(
      async () => {
        throw new Error(`${reason}: postgres://user:secret@private/db`);
      },
      async (base) => {
        const response = await fetch(`${base}/health`);
        assert.equal(response.status, 503);
        assert.deepEqual(await response.json(), {
          status: "unavailable",
          release,
        });
      },
    );
  });
}

test("health is GET-only and cannot bypass sync auth or existing CORS", async () => {
  let queries = 0;
  await withApp(
    async () => {
      queries++;
      return { rows: [] };
    },
    async (base) => {
      for (const method of ["POST", "PUT", "DELETE", "HEAD", "OPTIONS"]) {
        assert.equal((await fetch(`${base}/health`, { method })).status, 404);
      }
      for (const [path, method] of [
        ["/v1/sync/pull", "GET"],
        ["/v1/sync/push", "POST"],
      ]) {
        const response = await fetch(base + path, { method });
        assert.equal(response.status, 401);
        assert.deepEqual(await response.json(), {
          error: "Bearer token required",
        });
      }
      assert.equal(
        (
          await fetch(`${base}/v1/sync/pull`, {
            headers: { origin: "https://untrusted.example.invalid" },
          })
        ).status,
        403,
      );
      const preflight = await fetch(`${base}/v1/sync/push`, {
        method: "OPTIONS",
        headers: {
          origin: "https://app.example.invalid",
          "access-control-request-method": "POST",
          "access-control-request-headers": "authorization,content-type",
        },
      });
      assert.equal(preflight.status, 204);
      assert.equal(
        preflight.headers.get("access-control-allow-origin"),
        "https://app.example.invalid",
      );
    },
  );
  assert.equal(queries, 0);
});

test("release configuration rejects arbitrary strings without echoing their contents", () => {
  for (const invalid of [
    "postgres://user:secret@host/db",
    "a".repeat(39),
    "",
  ]) {
    assert.throws(() => createApp({} as Pool, auth, [], { release: invalid }), {
      message: "Invalid release identifier",
    });
  }
});

test("startup rejects invalid configuration without logging its secret contents", () => {
  const result = spawnSync(
    process.execPath,
    [
      "--import",
      "tsx",
      fileURLToPath(new URL("../src/main.ts", import.meta.url)),
    ],
    {
      encoding: "utf8",
      timeout: 5000,
      env: {
        ...process.env,
        AUTH_ISSUER: "SYNTHETIC_PRIVATE_CONFIGURATION",
        AUTH_JWKS_URL: "https://auth.example.invalid/jwks",
      },
    },
  );
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.equal(
    result.stderr,
    "Backend startup failed; check runtime configuration and database readiness\n",
  );
});
