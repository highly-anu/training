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
  session_key    TEXT NOT NULL,
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercises      JSONB NOT NULL DEFAULT '{}',
  notes          TEXT DEFAULT '',
  fatigue_rating INTEGER,
  completed_at   TIMESTAMPTZ,
  PRIMARY KEY (session_key, user_id)
);

ALTER TABLE session_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users access own session logs"
  ON session_logs FOR ALL
  USING (user_id = auth.uid());


CREATE TABLE IF NOT EXISTS daily_bio (
  date       DATE NOT NULL,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  resting_hr INTEGER,
  hrv        REAL,
  notes      TEXT,
  PRIMARY KEY (date, user_id)
);

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
