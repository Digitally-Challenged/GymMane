-- A connection generation is not an athlete identity: retain job ownership even
-- after disconnect clears the current connection's athlete.
ALTER TABLE strava_jobs ADD COLUMN athlete_id text;
ALTER TABLE strava_jobs ADD COLUMN post_intent_at timestamptz;
UPDATE strava_jobs j SET athlete_id=c.athlete_id
FROM strava_connections c
WHERE j.account_id=c.account_id AND j.generation=c.generation;
-- Old attempts were incremented before every possible POST. Treat any such
-- attempt conservatively; a prior generation's athlete cannot be reconstructed.
UPDATE strava_jobs SET post_intent_at=created_at
WHERE attempts>0 OR upload_id IS NOT NULL OR activity_id IS NOT NULL
   OR status IN ('sending','processing','confirmed','unknown');
