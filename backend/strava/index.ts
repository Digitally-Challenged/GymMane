import { randomBytes } from "node:crypto";
import type { Pool, PoolClient } from "pg";
import type { BackendModule } from "../src/modules.js";
import { assert, HttpError, object, uuid } from "../src/protocol.js";
import { stateDigest, TokenCipher } from "./crypto.js";
import {
  active,
  connection,
  locked,
  publicJob,
  transaction,
  type Job,
} from "./database.js";
import { strengthPayload, UnsupportedWorkout } from "./payload.js";
import { Provider, type Config } from "./provider.js";
import { providerId, transport, type Transport } from "./transport.js";
import { UploadWorker } from "./worker.js";
function configFrom(env: NodeJS.ProcessEnv): Config | null {
  const names = [
    "STRAVA_CLIENT_ID",
    "STRAVA_CLIENT_SECRET",
    "STRAVA_REDIRECT_URI",
    "STRAVA_TOKEN_KEY",
  ] as const;
  if (names.every((name) => !env[name])) return null;
  if (names.some((name) => !env[name]))
    throw new Error("All Strava configuration values are required");
  if (!/^\d+$/.test(env.STRAVA_CLIENT_ID!))
    throw new Error("Invalid STRAVA_CLIENT_ID");
  const redirect = new URL(env.STRAVA_REDIRECT_URI!);
  if (
    redirect.protocol !== "https:" ||
    redirect.pathname !== "/v1/strava/callback" ||
    redirect.search ||
    redirect.hash ||
    redirect.username ||
    redirect.password
  )
    throw new Error(
      "STRAVA_REDIRECT_URI must be HTTPS /v1/strava/callback without query or credentials",
    );
  return {
    clientId: env.STRAVA_CLIENT_ID!,
    clientSecret: env.STRAVA_CLIENT_SECRET!,
    redirectUri: redirect.toString(),
    cipher: new TokenCipher(env.STRAVA_TOKEN_KEY!),
  };
}
export function createStravaModule(
  pool: Pool,
  env: NodeJS.ProcessEnv = process.env,
  fetch: Transport = transport,
) {
  const config = configFrom(env);
  const provider = config ? new Provider(config, fetch) : null;
  const worker = provider ? new UploadWorker(pool, provider) : null;
  const requireProvider = () => {
    if (!provider) throw new HttpError(503, "Strava is not configured");
    return provider;
  };
  const run = <T>(account: string, fn: (db: PoolClient) => Promise<T>) =>
    locked(pool, account, async (db) => {
      await active(db, account);
      return fn(db);
    });
  const register: BackendModule = (registry) => {
    registry.authenticated(
      "GET",
      "/v1/strava/status",
      async ({ accountId }) => {
        if (!config)
          return {
            configured: false,
            connected: false,
            athleteId: null,
            status: "disconnected",
            jobs: [],
          };
        return run(accountId, async (db) => {
          const c = await connection(db, accountId);
          const jobs = await db.query<Job>(
            "SELECT * FROM strava_jobs WHERE account_id=$1 ORDER BY created_at DESC LIMIT 100",
            [accountId],
          );
          return {
            configured: true,
            connected: c.status === "connected" && !c.refresh_pending,
            athleteId: c.athlete_id,
            status: c.refresh_pending ? "needsAuthorization" : c.status,
            jobs: jobs.rows.map(publicJob),
          };
        });
      },
    );
    registry.authenticated(
      "POST",
      "/v1/strava/connect",
      async ({ accountId }) => {
        const p = requireProvider();
        return run(accountId, async (db) => {
          const c = await connection(db, accountId);
          const state = randomBytes(32).toString("base64url");
          const expiresAt = new Date(Date.now() + 600000).toISOString();
          await transaction(db, async () => {
            await db.query(
              "DELETE FROM strava_states WHERE account_id=$1 OR expires_at<now()",
              [accountId],
            );
            await db.query(
              "INSERT INTO strava_states(digest,account_id,generation,expires_at) VALUES($1,$2,$3,$4)",
              [stateDigest(state), accountId, c.generation, expiresAt],
            );
          });
          const url = new URL("https://www.strava.com/oauth/authorize");
          url.search = new URLSearchParams({
            client_id: p.config.clientId,
            redirect_uri: p.config.redirectUri,
            response_type: "code",
            approval_prompt: "force",
            scope: "activity:write",
            state,
          }).toString();
          return { authorizationUrl: url.toString(), expiresAt };
        });
      },
    );
    registry.publicCallback(
      "GET",
      "/v1/strava/callback",
      async (_request, url) => {
        requireProvider();
        const state = url.searchParams.get("state");
        assert(
          state &&
            /^[\w-]{43}$/.test(state) &&
            url.searchParams.getAll("state").length === 1,
          "Invalid OAuth state",
        );
        const result = await pool.query(
          "UPDATE strava_states SET consumed=true WHERE digest=$1 AND NOT consumed AND expires_at>now() RETURNING account_id",
          [stateDigest(state)],
        );
        if (!result.rows.length)
          throw new HttpError(400, "OAuth state expired or already used");
        return result.rows[0].account_id as string;
      },
      async ({ accountId, url }) =>
        run(accountId, async (db) => {
          const p = requireProvider();
          const c = await connection(db, accountId);
          const state = await db.query(
            "DELETE FROM strava_states WHERE digest=$1 AND account_id=$2 AND consumed RETURNING generation",
            [stateDigest(url.searchParams.get("state")!), accountId],
          );
          if (
            !state.rows.length ||
            String(state.rows[0].generation) !== String(c.generation)
          )
            throw new HttpError(
              400,
              "Connection changed; start authorization again",
            );
          if (url.searchParams.has("error"))
            throw new HttpError(400, "Strava authorization denied");
          const code = url.searchParams.get("code");
          assert(
            code &&
              code.length <= 2048 &&
              url.searchParams.getAll("code").length === 1,
            "Missing authorization code",
          );
          assert(
            (url.searchParams.get("scope") ?? "")
              .split(/[ ,]+/)
              .includes("activity:write"),
            "Strava activity:write permission is required",
          );
          const tokens = await p.tokenRequest(db, {
            grant_type: "authorization_code",
            code,
          });
          const athlete = object(tokens.athlete)
            ? providerId(tokens.athlete.id)
            : null;
          if (!athlete)
            throw new HttpError(502, "Invalid Strava athlete response");
          await transaction(db, async () => {
            // One athlete cannot be attached to multiple GymMane accounts.
            const owner = await db.query(
              "SELECT account_id FROM strava_connections WHERE athlete_id=$1 AND account_id<>$2",
              [athlete, accountId],
            );
            if (owner.rows.length)
              throw new HttpError(
                409,
                "Strava athlete already linked to another account",
              );
            await db.query(
              "UPDATE strava_connections SET generation=generation+1,status='connected',athlete_id=$2,tokens=$3,refresh_pending=false WHERE account_id=$1",
              [accountId, athlete, p.config.cipher.seal(tokens, accountId)],
            );
            await db.query(
              "UPDATE strava_jobs SET status=CASE WHEN status='sending' THEN 'unknown' ELSE 'needsAuthorization' END,message='Connection replaced; no automatic resend' WHERE account_id=$1 AND status IN ('queued','sending','processing')",
              [accountId],
            );
          });
          return { connected: true };
        }),
    );
    registry.authenticated(
      "POST",
      "/v1/strava/disconnect",
      async ({ accountId }) =>
        run(accountId, async (db) => {
          const p = requireProvider();
          const c = await connection(db, accountId);
          await transaction(db, async () => {
            await db.query(
              "UPDATE strava_connections SET generation=generation+1,status='disconnected',athlete_id=NULL,tokens=NULL,refresh_pending=false WHERE account_id=$1",
              [accountId],
            );
            await db.query("DELETE FROM strava_states WHERE account_id=$1", [
              accountId,
            ]);
            await db.query(
              "UPDATE strava_jobs SET status=CASE WHEN status='sending' THEN 'unknown' ELSE 'needsAuthorization' END,message='Disconnected; delivery stopped' WHERE account_id=$1 AND status IN ('queued','sending','processing')",
              [accountId],
            );
          });
          let revocationStatus = "notNeeded";
          if (c.tokens) {
            try {
              const token = p.config.cipher.open(
                c.tokens,
                accountId,
              ).access_token;
              await p.request(db, "/oauth/deauthorize", {
                method: "POST",
                body: new URLSearchParams({ access_token: token }),
              });
              revocationStatus = "revoked";
            } catch {
              revocationStatus = "unconfirmed";
            }
          }
          return { connected: false, revocationStatus };
        }),
    );
    registry.authenticated(
      "POST",
      "/v1/strava/export",
      async ({ accountId, readJson }) => {
        requireProvider();
        const raw = await readJson();
        assert(
          object(raw) &&
            Object.keys(raw).length === 2 &&
            typeof raw.workoutId === "string" &&
            uuid.test(raw.workoutId) &&
            Number.isSafeInteger(raw.revision) &&
            (raw.revision as number) > 0,
        );
        const id = raw.workoutId.toLowerCase();
        return run(accountId, async (db) => {
          const c = await connection(db, accountId);
          const source = (
            await db.query(
              "SELECT payload,revision,deleted FROM sync_entities WHERE account_id=$1 AND entity_type='workout' AND entity_id=$2",
              [accountId, id],
            )
          ).rows[0];
          if (!source || source.deleted)
            throw new HttpError(404, "Workout not found");
          if (Number(source.revision) !== raw.revision)
            throw new HttpError(409, "Sync the latest workout revision first");
          const existing = (
            await db.query<Job>(
              "SELECT * FROM strava_jobs WHERE account_id=$1 AND workout_id=$2 ORDER BY revision DESC",
              [accountId, id],
            )
          ).rows;
          const same = existing.find(
            (j) => Number(j.revision) === raw.revision,
          );
          if (same) return publicJob(same);
          if (c.status !== "connected" || c.refresh_pending)
            throw new HttpError(409, "Connect Strava first");
          // Even across generations and edits, never duplicate a potentially sent activity.
          let status = "queued",
            message: string | null = null,
            payload: object | null = null;
          if (
            existing.some(
              (j) =>
                j.upload_id ||
                [
                  "sending",
                  "processing",
                  "confirmed",
                  "unknown",
                  "needsAuthorization",
                ].includes(j.status),
            )
          ) {
            status = "unsupported";
            message =
              "Previously exported workout; edit or delete it manually in Strava";
          } else
            try {
              payload = strengthPayload(source.payload);
            } catch (error) {
              if (!(error instanceof UnsupportedWorkout)) throw error;
              status = "unsupported";
              message = error.message;
            }
          const name =
            typeof source.payload.n === "string"
              ? source.payload.n.slice(0, 200)
              : "GymMane strength workout";
          const job = (
            await db.query<Job>(
              "INSERT INTO strava_jobs(account_id,workout_id,revision,generation,status,payload,name,message) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *",
              [
                accountId,
                id,
                raw.revision,
                c.generation,
                status,
                payload,
                name,
                message,
              ],
            )
          ).rows[0];
          return publicJob(job);
        });
      },
    );
  };
  return {
    register,
    tick: async () => {
      await worker?.tick();
    },
  };
}
