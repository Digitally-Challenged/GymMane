import { Pool } from "pg";
import { createApp } from "./server.js";
import { loadRuntimeModules, startModuleJobs } from "./runtime-modules.js";
function required(name: string) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} required`);
  return value;
}
let pool: Pool | undefined;
async function main() {
  const issuer = required("AUTH_ISSUER");
  const jwksUrl = required("AUTH_JWKS_URL");
  for (const value of [issuer, jwksUrl]) {
    const url = new URL(value);
    if (
      url.protocol !== "https:" &&
      !(
        process.env.ALLOW_LOCAL_AUTH === "true" &&
        ["localhost", "127.0.0.1"].includes(url.hostname) &&
        url.protocol === "http:"
      )
    )
      throw new Error("Auth URLs require HTTPS (local test exception only)");
  }
  const port = Number(process.env.PORT ?? 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error("Invalid PORT");
  pool = new Pool({
    connectionString: required("DATABASE_URL"),
    max: 10,
    connectionTimeoutMillis: 5000,
    statement_timeout: 15000,
  });
  pool.on("error", () => console.error("Idle database connection failed"));
  await pool.query("SELECT 1 FROM backend_migrations LIMIT 1");
  const modules = await loadRuntimeModules(pool, process.env);
  const server = createApp(
    pool,
    {
      issuer,
      jwksUrl,
      audience: required("AUTH_AUDIENCE"),
    },
    modules.map((module) => module.register),
    {
      release: process.env.GYMMANE_RELEASE ?? "development",
      allowedOrigins: (process.env.CORS_ALLOWED_ORIGINS ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean),
    },
  );
  const stopJobs = startModuleJobs(modules);
  server.listen(port, process.env.HOST ?? "127.0.0.1", () =>
    console.log(`Sync backend listening on port ${port}`),
  );
  for (const signal of ["SIGINT", "SIGTERM"])
    process.once(signal, () => {
      server.close(() => {
        void stopJobs().then(() => pool!.end());
      });
    });
}
try {
  await main();
} catch {
  // Startup failures may contain connection strings or provider configuration.
  console.error(
    "Backend startup failed; check runtime configuration and database readiness",
  );
  await pool?.end();
  process.exitCode = 1;
}
