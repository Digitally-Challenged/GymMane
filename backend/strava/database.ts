import type { Pool, PoolClient } from "pg";
import { HttpError } from "../src/protocol.js";
export interface Connection {
  account_id: string;
  generation: string;
  status: string;
  athlete_id: string | null;
  tokens: string | null;
  refresh_pending: boolean;
}
export interface Job {
  account_id: string;
  workout_id: string;
  revision: string;
  generation: string;
  status: string;
  payload: object;
  name: string;
  upload_id: string | null;
  activity_id: string | null;
  message: string | null;
  attempts: number;
}
export function publicJob(job: Job) {
  return {
    workoutId: job.workout_id,
    revision: Number(job.revision),
    status: job.status,
    uploadId: job.upload_id,
    activityId: job.activity_id,
    message: job.message,
  };
}
// Session locks deliberately span COMMIT before an external side effect. A
// transaction-only lock would release the fence just before sending the request.
export async function locked<T>(
  pool: Pool,
  account: string,
  fn: (db: PoolClient) => Promise<T>,
  tryOnly = false,
): Promise<T | undefined> {
  const db = await pool.connect();
  let acquired = false;
  let broken = false;
  try {
    if (tryOnly)
      acquired = (
        await db.query(
          "SELECT pg_try_advisory_lock(hashtextextended($1, 98173)) AS ok",
          [account],
        )
      ).rows[0].ok;
    else {
      await db.query("SELECT pg_advisory_lock(hashtextextended($1, 98173))", [
        account,
      ]);
      acquired = true;
    }
    if (!acquired) return;
    return await fn(db);
  } finally {
    if (acquired) {
      try {
        await db.query(
          "SELECT pg_advisory_unlock(hashtextextended($1, 98173))",
          [account],
        );
      } catch {
        broken = true;
      }
    }
    db.release(broken);
  }
}
export async function active(db: PoolClient, account: string) {
  const result = await db.query(
    "SELECT disabled FROM sync_accounts WHERE account_id=$1",
    [account],
  );
  if (!result.rows.length || result.rows[0].disabled)
    throw new HttpError(403, "Account unavailable");
}
export async function connection(
  db: PoolClient,
  account: string,
): Promise<Connection> {
  await db.query(
    "INSERT INTO strava_connections(account_id) VALUES($1) ON CONFLICT DO NOTHING",
    [account],
  );
  return (
    await db.query<Connection>(
      "SELECT * FROM strava_connections WHERE account_id=$1",
      [account],
    )
  ).rows[0];
}
export async function transaction<T>(
  db: PoolClient,
  fn: () => Promise<T>,
): Promise<T> {
  await db.query("BEGIN");
  try {
    const value = await fn();
    await db.query("COMMIT");
    return value;
  } catch (error) {
    await db.query("ROLLBACK");
    throw error;
  }
}
