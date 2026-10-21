import type { Pool, PoolClient } from "pg";
import { active, connection, locked, type Job } from "./database.js";
import { Provider } from "./provider.js";
import { ProviderError, providerId } from "./transport.js";
const MAX_ATTEMPTS = 30;
export class UploadWorker {
  constructor(
    private pool: Pool,
    private provider: Provider,
  ) {}
  async tick() {
    // At most four independent accounts per tick. Locks make multiple processes
    // safe; no request remains in flight after tick resolves.
    const due = await this.pool.query<{ account_id: string }>(
      "SELECT account_id FROM strava_jobs WHERE status IN ('queued','sending','processing') AND next_attempt<=now() GROUP BY account_id ORDER BY min(next_attempt) LIMIT 4",
    );
    await Promise.all(
      due.rows.map((row) =>
        locked(
          this.pool,
          row.account_id,
          (db) => this.run(db, row.account_id),
          true,
        ),
      ),
    );
  }
  private async update(
    db: PoolClient,
    j: Job,
    status: string,
    message: string | null = null,
    delay = 5,
    uploadId = j.upload_id,
    activityId = j.activity_id,
  ) {
    await db.query(
      "UPDATE strava_jobs SET status=$4,message=$5,next_attempt=now()+$6*interval '1 second',upload_id=$7,activity_id=$8 WHERE account_id=$1 AND workout_id=$2 AND revision=$3",
      [
        j.account_id,
        j.workout_id,
        j.revision,
        status,
        message,
        delay,
        uploadId,
        activityId,
      ],
    );
  }
  private async run(db: PoolClient, account: string) {
    // Holding the account session lock proves any prior sending worker is gone.
    await db.query(
      "UPDATE strava_jobs SET status='unknown',message='Submission interrupted; check Strava manually before any further export' WHERE account_id=$1 AND status='sending'",
      [account],
    );
    try {
      await active(db, account);
    } catch {
      await db.query(
        "UPDATE strava_jobs SET status='needsAuthorization',message='Account unavailable' WHERE account_id=$1 AND status IN ('queued','processing')",
        [account],
      );
      return;
    }
    const c = await connection(db, account);
    await db.query(
      "UPDATE strava_jobs SET status='needsAuthorization',message='Connection changed; no automatic resend' WHERE account_id=$1 AND status IN ('queued','processing') AND generation<>$2",
      [account, c.generation],
    );
    const j = (
      await db.query<Job>(
        "SELECT * FROM strava_jobs WHERE account_id=$1 AND status IN ('queued','processing') AND next_attempt<=now() ORDER BY next_attempt LIMIT 1",
        [account],
      )
    ).rows[0];
    if (!j) return;
    if (j.attempts >= MAX_ATTEMPTS) {
      await this.update(
        db,
        j,
        j.upload_id ? "unknown" : "failed",
        "Retry limit reached; check Strava manually",
      );
      return;
    }
    let token: string | null;
    try {
      token = await this.provider.access(db, c);
    } catch (error) {
      if (error instanceof ProviderError) {
        await this.update(
          db,
          j,
          j.status,
          "Rate limited",
          Math.max(5, (error.retryAt.getTime() - Date.now()) / 1000),
        );
        return;
      }
      throw error;
    }
    if (!token) {
      await this.update(
        db,
        j,
        "needsAuthorization",
        "Reconnect Strava; no automatic resend",
      );
      return;
    }
    if (!j.upload_id) {
      // Stored revision must still exist and match before the first submission.
      const source = await db.query(
        "SELECT revision,deleted FROM sync_entities WHERE account_id=$1 AND entity_type='workout' AND entity_id=$2",
        [account, j.workout_id],
      );
      if (
        !source.rows.length ||
        source.rows[0].deleted ||
        String(source.rows[0].revision) !== String(j.revision)
      ) {
        await this.update(
          db,
          j,
          "unsupported",
          "Workout changed or was deleted before upload",
        );
        return;
      }
    }
    // Mark sending durably before fetch. No automatic retry of ambiguous POSTs.
    await db.query(
      "UPDATE strava_jobs SET status=$4,attempts=attempts+1 WHERE account_id=$1 AND workout_id=$2 AND revision=$3",
      [
        account,
        j.workout_id,
        j.revision,
        j.upload_id ? "processing" : "sending",
      ],
    );
    try {
      let result: Record<string, unknown>;
      if (j.upload_id)
        result = await this.provider.request(
          db,
          `/api/v3/uploads/${j.upload_id}`,
          { method: "GET", headers: { Authorization: `Bearer ${token}` } },
        );
      else {
        const body = new FormData();
        body.set(
          "file",
          new Blob([JSON.stringify(j.payload)], { type: "application/json" }),
          `${j.workout_id}.json`,
        );
        body.set("data_type", "json");
        body.set("sport_type", "WeightTraining");
        body.set("name", j.name);
        body.set(
          "external_id",
          `gymmane-${account}-${j.workout_id}-r${j.revision}`,
        );
        result = await this.provider.request(db, "/api/v3/uploads", {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body,
        });
      }
      const upload =
        providerId(result.id_str) ?? providerId(result.id) ?? j.upload_id;
      const activity = providerId(result.activity_id);
      if (!upload) {
        await this.update(
          db,
          j,
          "unknown",
          "Missing upload identifier; check Strava manually",
        );
        return;
      }
      if (result.error) {
        await this.update(
          db,
          j,
          "failed",
          "Strava rejected the upload; inspect it in Strava",
          5,
          upload,
        );
        return;
      }
      await this.update(
        db,
        j,
        activity ? "confirmed" : "processing",
        null,
        Math.min(300, 5 * 2 ** Math.min(j.attempts, 6)),
        upload,
        activity,
      );
    } catch (error) {
      if (error instanceof ProviderError && error.status === 429) {
        await this.update(
          db,
          j,
          j.upload_id ? "processing" : "queued",
          "Rate limited",
          Math.max(5, (error.retryAt.getTime() - Date.now()) / 1000),
        );
      } else if (
        error instanceof ProviderError &&
        [401, 403].includes(error.status)
      ) {
        await this.provider.invalidate(db, account);
        await this.update(
          db,
          j,
          "needsAuthorization",
          "Strava authorization expired",
        );
      } else if (
        error instanceof ProviderError &&
        error.status >= 400 &&
        error.status < 500
      ) {
        await this.update(db, j, "failed", "Strava rejected the request");
      } else if (j.upload_id) {
        await this.update(
          db,
          j,
          "processing",
          "Status check will retry",
          Math.min(300, 5 * 2 ** Math.min(j.attempts, 6)),
        );
      } else
        await this.update(
          db,
          j,
          "unknown",
          "Upload outcome unknown; check Strava manually. Automatic resend disabled",
        );
    }
  }
}
