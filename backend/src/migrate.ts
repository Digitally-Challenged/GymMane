import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { Pool } from "pg";
export async function migrate(
  pool: Pool,
  directory = new URL(`file://${resolve("migrations")}/`),
) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(682417302)");
    await client.query(
      "CREATE TABLE IF NOT EXISTS backend_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    for (const name of (await readdir(directory))
      .filter((n) => /^\d+.*\.sql$/.test(n))
      .sort()) {
      if (
        (
          await client.query("SELECT 1 FROM backend_migrations WHERE name=$1", [
            name,
          ])
        ).rowCount
      )
        continue;
      await client.query(await readFile(new URL(name, directory), "utf8"));
      await client.query("INSERT INTO backend_migrations(name) VALUES($1)", [
        name,
      ]);
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL required");
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  // CLI source and compiled runtime have different depths; resolve from backend cwd.
  try {
    await migrate(pool, new URL(`file://${resolve("migrations")}/`));
  } finally {
    await pool.end();
  }
}
