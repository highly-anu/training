-- Cross-source workout dedup.
--
-- A workout's id embeds its source (src/workout_ids.py), so one morning run
-- arriving via the Garmin webhook, Apple Health, Strava and a manual .fit
-- upload becomes four rows. These columns let the write path recognise that
-- and merge instead.
--
-- Both columns are NULLABLE and there is deliberately NO unique index on
-- dedupe_key: the table already contains duplicates that predate this, so a
-- unique index would fail to build on real data. A unique partial index
-- (WHERE canonical_id IS NULL) is only safe after a cleanup pass.
--
-- Run: python run_migration.py 003_workout_dedupe

ALTER TABLE workouts ADD COLUMN IF NOT EXISTS dedupe_key   TEXT;

-- Points at the row this one was folded into. NULL means this row IS the
-- canonical one. Losers are kept, never deleted — workout_matches and
-- session_logs reference workout ids.
ALTER TABLE workouts ADD COLUMN IF NOT EXISTS canonical_id TEXT;

CREATE INDEX IF NOT EXISTS idx_workouts_dedupe
    ON workouts (user_id, dedupe_key);

-- The dedup decision is made over a +/- 5 minute start-time window rather than
-- on dedupe_key alone, so that lookup needs its own index.
CREATE INDEX IF NOT EXISTS idx_workouts_user_start
    ON workouts (user_id, start_time);


-- Weak match suggestions from the server-side matcher.
--
-- Kept out of workout_matches on purpose: a dozen readers treat "has a
-- workout_matches row that isn't 'rejected'" as "is matched", so a 'pending'
-- confidence there would render as a confirmed match everywhere.
CREATE TABLE IF NOT EXISTS workout_match_suggestions (
    imported_workout_id TEXT NOT NULL,
    user_id             TEXT NOT NULL,
    session_key         TEXT NOT NULL,
    score               INTEGER NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (imported_workout_id, user_id)
);
