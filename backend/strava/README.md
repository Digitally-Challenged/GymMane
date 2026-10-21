# Strava module

Enable the shared runtime with `STRAVA_ENABLED=true`. Run backend migrations, including `002_strava.sql`, before startup. Configure all four server-only variables:

- `STRAVA_CLIENT_ID`: registered Strava application ID.
- `STRAVA_CLIENT_SECRET`: its secret.
- `STRAVA_REDIRECT_URI`: public HTTPS URL ending exactly `/v1/strava/callback`, on the callback domain configured in Strava; no query string.
- `STRAVA_TOKEN_KEY`: canonical base64 encoding of 32 cryptographically random bytes. Keep it stable in the deployment secret manager; changing it requires reconnecting existing accounts. Tokens use AES-256-GCM with account-bound authenticated data.

No real credentials, live connections or deployment are included. Live prerequisites are a deployed authenticated backend, migrated PostgreSQL, configured public callback domain, server secrets, and Strava athlete capacity for the intended users. The factory accepts an injected transport for deterministic tests; production URLs are fixed to Strava and requests time out after ten seconds. Runtime shutdown awaits active ticks. Test with `TEST_POSTGRES_PORT=55441 bash scripts/test-postgres.sh` from `backend/`; this starts and removes an isolated loopback database.

## Client API

Every route except the callback requires the existing backend Bearer JWT. The server derives account identity from that verified JWT. Never send an account ID or tokens in client requests.

| Method/path                  | Input                           | Result                                             |
| ---------------------------- | ------------------------------- | -------------------------------------------------- |
| POST `/v1/strava/connect`    | `{}`                            | `{authorizationUrl, expiresAt}`                    |
| GET `/v1/strava/status`      | none                            | `{configured, connected, athleteId, status, jobs}` |
| POST `/v1/strava/disconnect` | `{}`                            | `{connected:false, revocationStatus}`              |
| POST `/v1/strava/export`     | `{workoutId, revision}`         | Job                                                |
| GET `/v1/strava/callback`    | Strava's state/code/scope query | `{connected:true}` after successful authorization  |

A Job is `{workoutId, revision, status, uploadId, activityId, message}`. IDs are strings or null; revision is an integer. Status returns the latest 100 jobs; export of the same revision returns its existing job. Connection status is `disconnected`, `connected` or `needsAuthorization`. Job statuses are `queued`, `sending`, `processing`, `confirmed`, `unknown`, `needsAuthorization`, `failed`, `unsupported`.

Use a **Connect with Strava** action that opens `authorizationUrl` in an external authentication/browser session. Request only `activity:write`; the user can decline it. The callback returns JSON; tell the user to return to GymMane, and refresh status when the app resumes. State expires after ten minutes and is consumed once. A new connect attempt invalidates the previous one.

Offer export per completed workout with explicit user opt-in, after its latest revision has synced successfully. Upload requests load that account's persisted record; request bodies cannot supply workout data. Show queued/processing as pending, confirmed as delivered, and errors using the returned message. `unknown` means **check Strava manually** and must not offer blind resend. Editing or deleting an already exported workout is a manual Strava action; this module does not promise external set editing or deletion. Reconnect does not automatically restart stopped jobs. `revocationStatus:unconfirmed` means local delivery is fenced but the user should remove GymMane from Strava's authorized applications to confirm remote revocation.

## Data and delivery guarantees

Only persisted `origin:"gymmane"` sessions with recorded `dur > 0`, timezone-qualified end timestamp `d`, and `utcOffsetSeconds` are eligible. Start is end minus recorded duration. Native weights are kilograms. Supported catalog IDs map to documented movement identifiers; unsupported movements reject the entire export without dropping sets. Unknown/import provenance, missing timezone/duration, distance sets, invalid or empty sets are unsupported. Calories, active time, heart rate, and set start timestamps are never synthesized. Unmapped catalog exercises remain explicit unsupported cases; new mappings need semantic review.

PostgreSQL session advisory locks serialize each account across replicas, including OAuth/disconnect and rotating refresh. Refresh intent commits before exchange; ambiguous rotation requires authorization again. Jobs are durable and keyed by account, workout UUID and revision. Submission intent commits before POST; an interrupted sending job becomes unknown after restart. A known upload ID is preserved and polled rather than resubmitted. A 429 is retried after durable application-wide rate gates; POST timeouts, malformed success responses and 5xx results become unknown. Polls back off and stop after 30 attempts; at most four accounts are processed per tick. Disconnect increments connection generation, consumes pending state, clears tokens and fences pending work before attempting remote revocation.

Official references verified 2026-10-20: [authentication and rotating refresh](https://developers.strava.com/docs/authentication/), [strength JSON 1.0 and exercise identifiers](https://developers.strava.com/docs/uploads/), [upload API](https://developers.strava.com/docs/reference/#api-Uploads-createUpload), [rate limits](https://developers.strava.com/docs/rate-limits/). Deterministic transport tests establish local behavior, not live Strava interoperability.
