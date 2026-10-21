import type { PoolClient } from "pg";
import { assert, HttpError, object, uuid } from "../src/protocol.js";
import { publicJob, type Job } from "./database.js";

export function workoutReference(raw: unknown) {
  assert(
    object(raw) &&
      Object.keys(raw).length === 2 &&
      typeof raw.workoutId === "string" &&
      uuid.test(raw.workoutId) &&
      Number.isSafeInteger(raw.revision) &&
      (raw.revision as number) > 0,
  );
  return {
    workoutId: raw.workoutId.toLowerCase(),
    revision: raw.revision as number,
  };
}

// One predicate drives both the projection and the independently enforced retry.
// Never reconstruct submission safety from a mutable status or generation alone.
const selection = `SELECT j.*, COALESCE(
  c.status='connected' AND NOT c.refresh_pending AND c.tokens IS NOT NULL
  AND j.athlete_id=c.athlete_id AND j.payload IS NOT NULL
  AND j.post_intent_at IS NULL AND j.attempts=0
  AND j.upload_id IS NULL AND j.activity_id IS NULL
  AND NOT e.deleted AND e.revision=j.revision
  AND NOT EXISTS (
    SELECT 1 FROM strava_jobs other
    WHERE other.account_id=j.account_id AND other.workout_id=j.workout_id
      AND other.revision<>j.revision
      AND (other.post_intent_at IS NOT NULL OR other.attempts>0
        OR other.upload_id IS NOT NULL OR other.activity_id IS NOT NULL
        OR other.status IN ('sending','processing','confirmed','unknown'))
  ), false) AS retry_safe
FROM strava_jobs j
JOIN strava_connections c ON c.account_id=j.account_id
LEFT JOIN sync_entities e ON e.account_id=j.account_id
  AND e.entity_type='workout' AND e.entity_id=j.workout_id`;
export interface RetryJob extends Job {
  retry_safe: boolean;
}
export async function jobs(
  db: PoolClient,
  account: string,
  workoutId?: string,
) {
  const result = await db.query<RetryJob>(
    `${selection} WHERE j.account_id=$1 ${workoutId ? "AND j.workout_id=$2" : ""}
     ORDER BY j.created_at DESC, j.revision DESC ${workoutId ? "" : "LIMIT 100"}`,
    workoutId ? [account, workoutId] : [account],
  );
  return result.rows;
}
export function canRetry(job: RetryJob) {
  return (
    job.retry_safe && ["needsAuthorization", "failed"].includes(job.status)
  );
}
export function projectJob(job: RetryJob) {
  return { ...publicJob(job), canRetry: canRetry(job) };
}
export async function retry(db: PoolClient, account: string, raw: unknown) {
  const ref = workoutReference(raw);
  // Match SyncStore.push's lock, so validation and requeue form one durable
  // decision with respect to edits, deletion and account disabling.
  const owner = await db.query(
    "SELECT disabled FROM sync_accounts WHERE account_id=$1 FOR UPDATE",
    [account],
  );
  if (!owner.rows.length || owner.rows[0].disabled)
    throw new HttpError(403, "Account unavailable");
  const job = (await jobs(db, account, ref.workoutId)).find(
    (j) => Number(j.revision) === ref.revision,
  );
  if (!job) throw new HttpError(404, "Strava job not found");
  // A replay while still queued returns the same job; it does not reset its
  // schedule or attempts. Once submission starts, retry is always rejected.
  if (job.retry_safe && job.status === "queued") return projectJob(job);
  if (!canRetry(job))
    throw new HttpError(
      409,
      "This export cannot be retried safely; check Strava and the latest workout",
    );
  await db.query(
    `UPDATE strava_jobs SET status='queued',generation=c.generation,
       message=NULL,next_attempt=now()
     FROM strava_connections c WHERE strava_jobs.account_id=$1
       AND workout_id=$2 AND revision=$3 AND c.account_id=$1`,
    [account, ref.workoutId, ref.revision],
  );
  return projectJob({ ...job, status: "queued", message: null });
}
