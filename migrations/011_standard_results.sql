-- Results on the standards: a history the athlete can manage.
--
-- performance_logs has kept every dated value since it was created in
-- supabase/schema.sql (never in this folder), but a row said only what and
-- when: nothing could edit one, clearing a web field deleted a standard's
-- whole series, and the day a result counted for was its UTC timestamp's
-- (a day late every evening west of Greenwich).
--
-- source       manual | session | garmin | apple_watch | workout — who said it
-- session_uid  the planned session a test result was logged in (program history)
-- session_key  that session's legacy key, for a log written before history
-- workout_id   the imported workout a best effort came from
-- note         the athlete's words
-- input        what was typed: {"text": "4:58"} or {"kg": 140, "reps": 2,
--              "bodyweightKg": 82, "est": true}; `value` is always the
--              standard's unit, worked out from this on the server
-- logged_on    the athlete's day (computed in Python from their timezone;
--              never logged_at::date, which is the server's UTC day)
--
-- Run (local): python run_migration.py 011_standard_results
-- Run (production): psql "$(grep '^DATABASE_URL=' .env | cut -d= -f2-)" -v ON_ERROR_STOP=1 -f migrations/011_standard_results.sql
-- — run_migration.py layers .env.local over .env, so from a dev checkout it
-- migrates training_test, not production (docs/program-history-release.md).
-- Additive: nullable columns and defaults; existing rows read as `manual`
-- with logged_on NULL until scripts/backfill_performance_logged_on.py fills
-- it (readers fall back to logged_at's day in the athlete's timezone).
-- src/standards_store.py adds the same columns lazily.
-- user_id is UUID in production (schema.sql) and TEXT in a test database:
-- join it to TEXT-keyed tables in Python, never in SQL.

ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS source      TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS session_uid TEXT;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS session_key TEXT;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS workout_id  TEXT;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS note        TEXT;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS input       JSONB;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS logged_on   DATE;
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_performance_logs_user_standard
    ON performance_logs (user_id, benchmark_id, logged_at);

-- One result per standard per session: a re-saved test updates its result.
CREATE UNIQUE INDEX IF NOT EXISTS uq_performance_logs_user_standard_session
    ON performance_logs (user_id, benchmark_id, session_uid) WHERE session_uid IS NOT NULL;
