// The migration CLI can include database/provider details in exception messages.
// Run the same production migrator with a deliberately generic error boundary.
import { Pool } from "pg";
import { migrate } from "../dist/src/migrate.js";

let pool;
try {
  if (!process.env.DATABASE_URL) throw new Error();
  pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    connectionTimeoutMillis: 5000,
    statement_timeout: 60000,
  });
  await migrate(pool);
  console.log("GymMane migrations completed");
} catch {
  console.error("GymMane migration failed; API startup blocked");
  process.exitCode = 1;
} finally {
  await pool?.end();
}
