-- Training app Supabase schema
-- Run this in the Supabase SQL editor for your project.
-- Auth (auth.users table) is managed by Supabase automatically.

-- ─────────────────────────────────────────────────────────────────────────────
-- User profiles (replaces localStorage `training-profile`)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  training_level      TEXT NOT NULL DEFAULT 'intermediate',
  equipment           JSONB NOT NULL DEFAULT '[]',
  injury_flags        JSONB NOT NULL DEFAULT '[]',
  custom_injury_flags JSONB NOT NULL DEFAULT '[]',
  active_goal_id      TEXT,
  date_of_birth       DATE,
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own profile"
  ON user_profiles FOR ALL
  USING (id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────────
-- User programs (replaces localStorage `training-program`)
-- user_id is the PK — each user has exactly one active program.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_programs (
  user_id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_program     JSONB,
  program_start_date  DATE,
  event_date          DATE,
  source_goal_ids     JSONB NOT NULL DEFAULT '[]',
  source_goal_weights JSONB NOT NULL DEFAULT '{}',
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own program"
  ON user_programs FOR ALL
  USING (user_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────────
-- Health data (Phase 3 — migrate from health.db)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workouts (
  id                   TEXT NOT NULL,
  user_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source               TEXT NOT NULL,
  date                 DATE NOT NULL,
  start_time           TIMESTAMPTZ NOT NULL,
  end_time             TIMESTAMPTZ NOT NULL,
  duration_minutes     INTEGER NOT NULL,
  activity_type        TEXT NOT NULL,
  inferred_modality_id TEXT,
  hr_avg               REAL,
  hr_max               REAL,
  hr_min               REAL,
  calories             INTEGER,
  distance_value       REAL,
  distance_unit        TEXT,
  raw_data             JSONB NOT NULL DEFAULT '{}',
  gps_track            JSONB,
  elevation_gain       INTEGER,
  elevation_loss       INTEGER,
  hr_samples           JSONB,
  PRIMARY KEY (id, user_id)
);

ALTER TABLE workouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own workouts"
  ON workouts FOR ALL
  USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS session_logs (
  session_key       TEXT NOT NULL,
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercises         JSONB NOT NULL DEFAULT '{}',
  notes             TEXT DEFAULT '',
  fatigue_rating    INTEGER,
  completed_at      TIMESTAMPTZ,
  source            TEXT DEFAULT 'web',
  avg_hr            REAL,
  peak_hr           REAL,
  exercise_timeline JSONB,
  PRIMARY KEY (session_key, user_id)
);

-- Migrations for existing deployments:
-- ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'web';
-- ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS avg_hr REAL;
-- ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS peak_hr REAL;
-- ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS exercise_timeline JSONB;   -- migrations/008

ALTER TABLE session_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own session logs"
  ON session_logs FOR ALL
  USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS daily_bio (
  date                   DATE NOT NULL,
  user_id                UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  resting_hr             INTEGER,
  hrv                    REAL,
  notes                  TEXT,
  sleep_duration_min     INTEGER,
  deep_sleep_min         INTEGER,
  rem_sleep_min          INTEGER,
  light_sleep_min        INTEGER,
  awake_min              INTEGER,
  sleep_start            TIMESTAMPTZ,
  sleep_end              TIMESTAMPTZ,
  spo2_avg               REAL,
  respiratory_rate_avg   REAL,
  source                 TEXT NOT NULL DEFAULT 'manual',
  PRIMARY KEY (date, user_id)
);

-- Migration for existing deployments (safe to run on a table that already exists):
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS sleep_duration_min INTEGER;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS deep_sleep_min INTEGER;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS rem_sleep_min INTEGER;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS light_sleep_min INTEGER;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS awake_min INTEGER;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS sleep_start TIMESTAMPTZ;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS sleep_end TIMESTAMPTZ;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS spo2_avg REAL;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS respiratory_rate_avg REAL;
-- ALTER TABLE daily_bio ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual';

ALTER TABLE daily_bio ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own bio logs"
  ON daily_bio FOR ALL
  USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS workout_matches (
  imported_workout_id TEXT NOT NULL,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_key         TEXT NOT NULL,
  match_confidence    TEXT NOT NULL,
  matched_at          TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (imported_workout_id, user_id)
);

ALTER TABLE workout_matches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own workout matches"
  ON workout_matches FOR ALL
  USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS performance_logs (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  benchmark_id TEXT NOT NULL,
  value        REAL NOT NULL,
  logged_at    TIMESTAMPTZ NOT NULL
);

ALTER TABLE performance_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own performance logs"
  ON performance_logs FOR ALL
  USING (user_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────────
-- Strava OAuth tokens (Phase 4 — migrate from oauth.db)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS strava_tokens (
  user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  access_token    TEXT NOT NULL,
  refresh_token   TEXT NOT NULL,
  expires_at      BIGINT NOT NULL,
  athlete_id      TEXT,
  athlete_name    TEXT,
  athlete_profile TEXT,
  last_sync_at    TIMESTAMPTZ
);

ALTER TABLE strava_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own strava tokens"
  ON strava_tokens FOR ALL
  USING (user_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────────
-- Cross-source workout dedup (migrations/003_workout_dedupe.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- A workout's id embeds its source, so one activity arriving via the Garmin
-- webhook, Apple Health, Strava and a manual .fit upload becomes four rows.
-- dedupe_key buckets them; canonical_id marks the ones folded into another.
-- Deliberately no UNIQUE index: existing data already contains duplicates.
-- ALTER TABLE workouts ADD COLUMN IF NOT EXISTS dedupe_key   TEXT;
-- ALTER TABLE workouts ADD COLUMN IF NOT EXISTS canonical_id TEXT;
-- CREATE INDEX IF NOT EXISTS idx_workouts_dedupe     ON workouts (user_id, dedupe_key);
-- CREATE INDEX IF NOT EXISTS idx_workouts_user_start ON workouts (user_id, start_time);


-- Weak matches from the server-side matcher. Kept out of workout_matches
-- because a dozen readers treat "row that isn't 'rejected'" as "is matched".
CREATE TABLE IF NOT EXISTS workout_match_suggestions (
  imported_workout_id TEXT NOT NULL,
  user_id             TEXT NOT NULL,
  session_key         TEXT NOT NULL,
  score               INTEGER NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (imported_workout_id, user_id)
);


-- ─────────────────────────────────────────────────────────────────────────────
-- Program history (migrations/005_program_history.sql + 006_session_log_scope.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- user_programs holds ONE row per athlete and is upserted, so generating a
-- program destroyed the previous one. Nothing recorded what had been planned,
-- and a planned session's only identity was the program-relative string
-- "{week_number}-{DayName}-{idx}" — which references nothing, so after a
-- regenerate every stored match silently re-pointed at whatever now occupied
-- that slot, and a workout dated inside a finished block could never be matched
-- at all. Three tables, because three different things were conflated.

-- The content: an immutable snapshot, deduplicated by skeleton hash.
CREATE TABLE IF NOT EXISTS program_versions (
  user_id       TEXT        NOT NULL,
  id            TEXT        NOT NULL,     -- sha256(user_id || skeleton)
  skeleton_hash TEXT        NOT NULL,
  content_hash  TEXT        NOT NULL,
  program_data  JSONB       NOT NULL,
  start_date    DATE        NOT NULL,
  week_count    INTEGER     NOT NULL DEFAULT 0,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, id)
);

-- The timeline: append-only; only effective_to is ever updated. Boundaries are
-- DATEs computed in Python, never activated_at::date — that cast uses the
-- server's TimeZone (UTC on fly.io) and would be a day out every evening west
-- of Greenwich. No unique constraint on (user_id, effective_from): two
-- regenerates in one day must be able to leave a zero-length interval.
CREATE TABLE IF NOT EXISTS program_activations (
  id                 BIGSERIAL   PRIMARY KEY,
  user_id            TEXT        NOT NULL,
  program_version_id TEXT        NOT NULL,
  lineage_id         TEXT        NOT NULL,
  effective_from     DATE        NOT NULL,
  effective_to       DATE,
  activated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source             TEXT        NOT NULL DEFAULT 'put',
  source_revision    TEXT,
  source_goal_ids    JSONB       NOT NULL DEFAULT '[]'::jsonb,
  goal_name          TEXT
);

-- The geometry: one row per planned session per version, on the calendar day it
-- fell on. session_uid is keyed on the week's ARRAY INDEX, never on
-- week_number — a program regenerated from an event date is numbered by its
-- absolute week, so one week_number can sit at two array indices and a key
-- built from it would collide. legacy_key is descriptive and NOT unique.
CREATE TABLE IF NOT EXISTS planned_sessions (
  user_id            TEXT    NOT NULL,
  session_uid        TEXT    NOT NULL,   -- '{version_id}:w{week_index}-{Day}-{idx}'
  program_version_id TEXT    NOT NULL,
  date               DATE    NOT NULL,
  week_index         INTEGER NOT NULL,
  week_number        INTEGER,
  day_name           TEXT    NOT NULL,
  session_index      INTEGER NOT NULL,
  legacy_key         TEXT    NOT NULL,
  modality           TEXT    NOT NULL DEFAULT '',
  archetype_id       TEXT,
  archetype_name     TEXT,
  duration_min       INTEGER NOT NULL DEFAULT 60,
  phase              TEXT,
  is_deload          BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (user_id, session_uid)
);

CREATE INDEX IF NOT EXISTS idx_prog_act_user_range    ON program_activations (user_id, effective_from, effective_to);
CREATE INDEX IF NOT EXISTS idx_prog_act_user_revision ON program_activations (user_id, source_revision);
CREATE INDEX IF NOT EXISTS idx_planned_user_date      ON planned_sessions (user_id, date);
CREATE INDEX IF NOT EXISTS idx_planned_legacy_date    ON planned_sessions (user_id, legacy_key, date);
CREATE INDEX IF NOT EXISTS idx_planned_version        ON planned_sessions (user_id, program_version_id);

ALTER TABLE program_versions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE planned_sessions    ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own program versions"    ON program_versions    FOR ALL USING (user_id = auth.uid()::text);
CREATE POLICY "users access own program activations" ON program_activations FOR ALL USING (user_id = auth.uid()::text);
CREATE POLICY "users access own planned sessions"    ON planned_sessions    FOR ALL USING (user_id = auth.uid()::text);

-- The durable link from what happened to what was planned. Nullable, and the
-- legacy session_key column stays and keeps being written, so every existing
-- client and stored row keeps working. Deliberately no FK: upsert_match
-- swallows exceptions, so a violation would be a silently dropped match.
-- ALTER TABLE workout_matches           ADD COLUMN IF NOT EXISTS session_uid TEXT;
-- ALTER TABLE workout_match_suggestions ADD COLUMN IF NOT EXISTS session_uid TEXT;
-- ALTER TABLE session_logs              ADD COLUMN IF NOT EXISTS session_uid TEXT;

-- 006: session_logs' primary key was (session_key, user_id), and session_key is
-- program-relative — so a log for week 3 Monday of a NEW program collided with
-- the old one's row and upsert_session_log MERGED the old block's set data into
-- it (`exercises || EXCLUDED.exercises`, `completed_at = GREATEST(...)`). A
-- session never performed could render as complete with someone else's numbers.
-- ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS log_key TEXT
--     GENERATED ALWAYS AS (COALESCE(session_uid, session_key)) STORED;
-- ALTER TABLE session_logs DROP CONSTRAINT IF EXISTS session_logs_pkey;
-- ALTER TABLE session_logs ADD  CONSTRAINT session_logs_pkey PRIMARY KEY (user_id, log_key);


-- ─────────────────────────────────────────────────────────────────────────────
-- Garmin Connect + shared OAuth state (migrations/004_garmin.sql)
-- ─────────────────────────────────────────────────────────────────────────────
-- oauth_state replaces oauth.py's local SQLite file, which did not survive a
-- fly.io restart, and carries Garmin's PKCE code_verifier.
CREATE TABLE IF NOT EXISTS oauth_state (
  state         TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  provider      TEXT NOT NULL,
  code_verifier TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- garmin_user_id is the reverse lookup the webhook depends on: Garmin
-- identifies the athlete by its own id and knows nothing about ours.
CREATE TABLE IF NOT EXISTS garmin_tokens (
  user_id                  TEXT PRIMARY KEY,
  oauth_version            SMALLINT NOT NULL DEFAULT 2,
  access_token             TEXT NOT NULL,
  refresh_token            TEXT,
  token_secret             TEXT,
  expires_at               BIGINT,
  refresh_token_expires_at BIGINT,
  garmin_user_id           TEXT UNIQUE,
  scope                    TEXT,
  athlete_name             TEXT,
  connected_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_sync_at             TIMESTAMPTZ,
  last_webhook_at          TIMESTAMPTZ
);

-- Durable queue: the webhook handler must return fast (gunicorn runs a single
-- sync worker) and the row is what survives a machine restart mid-batch.
CREATE TABLE IF NOT EXISTS garmin_webhook_events (
  id           BIGSERIAL PRIMARY KEY,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  event_type   TEXT NOT NULL,
  payload      JSONB NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  attempts     INTEGER NOT NULL DEFAULT 0,
  last_error   TEXT,
  processed_at TIMESTAMPTZ
);

-- Idempotency guard for redelivered pings.
CREATE TABLE IF NOT EXISTS garmin_activities (
  garmin_user_id TEXT NOT NULL,
  summary_id     TEXT NOT NULL,
  user_id        TEXT NOT NULL,
  workout_id     TEXT,
  imported_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (garmin_user_id, summary_id)
);
