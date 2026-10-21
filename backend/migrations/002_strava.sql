CREATE TABLE strava_connections (
  account_id uuid PRIMARY KEY REFERENCES sync_accounts,
  generation bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'disconnected' CHECK (status IN ('disconnected','connected','needsAuthorization')),
  athlete_id text UNIQUE,
  tokens text,
  refresh_pending boolean NOT NULL DEFAULT false
);
CREATE TABLE strava_states (
  digest text PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES strava_connections,
  generation bigint NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed boolean NOT NULL DEFAULT false
);
CREATE INDEX strava_states_expiry ON strava_states(expires_at);
CREATE TABLE strava_jobs (
  account_id uuid NOT NULL REFERENCES strava_connections,
  workout_id uuid NOT NULL,
  revision bigint NOT NULL CHECK (revision > 0),
  generation bigint NOT NULL,
  status text NOT NULL CHECK (status IN ('queued','sending','processing','confirmed','unknown','needsAuthorization','failed','unsupported')),
  payload jsonb,
  name text NOT NULL,
  upload_id text,
  activity_id text,
  message text,
  attempts integer NOT NULL DEFAULT 0,
  next_attempt timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(account_id,workout_id,revision)
);
CREATE INDEX strava_jobs_due ON strava_jobs(next_attempt) WHERE status IN ('queued','sending','processing');
-- Application-wide throttle survives process restarts and applies across replicas.
CREATE TABLE strava_throttle (id boolean PRIMARY KEY DEFAULT true CHECK(id), until_at timestamptz NOT NULL);
INSERT INTO strava_throttle VALUES (true, '-infinity');
REVOKE ALL ON strava_connections, strava_states, strava_jobs, strava_throttle FROM PUBLIC;
