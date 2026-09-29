-- Program history: which plan was in force when, and what it planned each day.
--
-- `user_programs` holds one row per athlete and src/db.py save_user_program
-- upserts it, so generating a program destroyed the previous one. Nothing
-- recorded what had been planned, and a planned session's only identity was the
-- program-relative string "{week_number}-{DayName}-{idx}" — which references
-- nothing, so after a regenerate every stored workout_matches row silently
-- re-pointed at whatever now occupied that slot. A workout arriving for a date
-- outside the *current* program was dropped by the matcher and could never be
-- matched afterwards.
--
-- Three tables, because three different things were conflated:
--
--   program_versions     the content — an immutable snapshot of one plan
--   program_activations  the timeline — append-only, DATE-valued intervals
--   planned_sessions     the geometry — one row per planned session per
--                        version, carrying the calendar date it fell on
--
-- Run: python run_migration.py 005_program_history
--
-- Additive and safe to run on live data: it creates new tables and adds only
-- NULLABLE columns to existing ones. The session_logs primary key move, which
-- is not additive, is 006 and must run after the backfill.

-- ─────────────────────────────────────────────────────────────────────────────
-- Content. Immutable, deduplicated by skeleton.
-- ─────────────────────────────────────────────────────────────────────────────
-- `id` is sha256(user_id || skeleton) — see src/program_history.version_id. The
-- user id is inside the hash as well as in the composite key so two athletes
-- running the same philosophy from the same Monday cannot collide.
--
-- skeleton_hash is identity: it covers the start date, each week's number,
-- phase and deload flag, and each day's (modality, archetype id, exercise ids).
-- content_hash covers the whole envelope. Same skeleton with different content
-- means the snapshot is stale, not that the plan is new, and program_data is
-- then refreshed in place — the one exception to immutability, and only ever by
-- a copy at least as rich (an iOS save strips `goal` and every `slot`).
CREATE TABLE IF NOT EXISTS program_versions (
    user_id       TEXT        NOT NULL,
    id            TEXT        NOT NULL,
    skeleton_hash TEXT        NOT NULL,
    content_hash  TEXT        NOT NULL,
    program_data  JSONB       NOT NULL,
    start_date    DATE        NOT NULL,
    week_count    INTEGER     NOT NULL DEFAULT 0,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Timeline. Append-only; only effective_to is ever updated.
-- ─────────────────────────────────────────────────────────────────────────────
-- Boundaries are DATEs computed in Python, never activated_at::date in SQL:
-- that cast uses the server's TimeZone (UTC on fly.io), so a 21:00 regenerate
-- at UTC-7 would land on tomorrow and the boundary would be a day out every
-- evening. activated_at is kept for audit only.
--
-- effective_from is the program's own start_date for the FIRST activation on an
-- athlete's timeline, so the program archived on first read owns its
-- already-elapsed weeks; anchoring it to NOW() instead would leave every
-- existing match unattributable and regress against today's behaviour, where
-- the matcher covers the program's whole span.
--
-- There is deliberately NO unique constraint on (user_id, effective_from): two
-- regenerates in one day must be able to produce a zero-length interval, which
-- the resolution query naturally returns nothing for.
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

CREATE INDEX IF NOT EXISTS idx_prog_act_user_range
    ON program_activations (user_id, effective_from, effective_to);

-- The short-circuit that keeps GET /api/user/program cheap: it already fetches
-- user_programs.updated_at as the revision, so one indexed lookup tells it the
-- stored program is already archived, before hashing a ~1 MB envelope.
CREATE INDEX IF NOT EXISTS idx_prog_act_user_revision
    ON program_activations (user_id, source_revision);

-- ─────────────────────────────────────────────────────────────────────────────
-- Geometry. One row per planned session per version.
-- ─────────────────────────────────────────────────────────────────────────────
-- session_uid is '{version_id}:w{week_index}-{Day}-{idx}' — the week's ARRAY
-- INDEX, never its week_number. week_number is not unique: src/generator.py
-- numbers weeks from `week_in_program` and, with an event date,
-- phase_calendar.build_remaining_schedule starts that at the athlete's absolute
-- program week, so a 16-week generate legitimately yields weeks[0..15] numbered
-- 16..31. Splice that onto the kept head and one week_number sits at two array
-- indices; keyed on it this primary key would collide and lose the version.
--
-- legacy_key ('3-Monday-0') is the program-relative key every existing client
-- already speaks. It is descriptive and NOT unique — resolution by legacy key
-- is always (user_id, legacy_key, date), and the date is what disambiguates.
--
-- No session_data column: it is redundant with program_versions.program_data,
-- and the web store PUTs on every drag-move, so carrying the session JSON here
-- would cost ~1 MB per edit. The flat columns are the matcher's hot path; the
-- rare detail read walks program_data by jsonb path.
CREATE TABLE IF NOT EXISTS planned_sessions (
    user_id            TEXT    NOT NULL,
    session_uid        TEXT    NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_planned_user_date
    ON planned_sessions (user_id, date);
CREATE INDEX IF NOT EXISTS idx_planned_legacy_date
    ON planned_sessions (user_id, legacy_key, date);
CREATE INDEX IF NOT EXISTS idx_planned_version
    ON planned_sessions (user_id, program_version_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- The durable link from what happened to what was planned.
-- ─────────────────────────────────────────────────────────────────────────────
-- Nullable, and the legacy session_key column stays and keeps being written, so
-- every existing client and every already-stored row keeps working. A reader
-- resolves session_uid first and falls back to (session_key, date).
--
-- Deliberately NO foreign key to planned_sessions: health_store.upsert_match
-- swallows exceptions, so a constraint violation would turn into a silently
-- dropped match. Same reasoning as 003's note on not constraining dirty data.
ALTER TABLE workout_matches            ADD COLUMN IF NOT EXISTS session_uid TEXT;
ALTER TABLE workout_match_suggestions  ADD COLUMN IF NOT EXISTS session_uid TEXT;
ALTER TABLE session_logs               ADD COLUMN IF NOT EXISTS session_uid TEXT;

CREATE INDEX IF NOT EXISTS idx_matches_session_uid
    ON workout_matches (user_id, session_uid);
CREATE INDEX IF NOT EXISTS idx_session_logs_session_uid
    ON session_logs (user_id, session_uid);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security, in the style of 001.
-- ─────────────────────────────────────────────────────────────────────────────
-- src/program_history.py also creates these tables lazily (the pattern
-- health_store uses for progression_snapshots) so a deploy that has not run
-- this migration still works. That path creates them WITHOUT policies, because
-- a test database has no `auth` schema — this file is the authority on RLS.
ALTER TABLE program_versions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE planned_sessions    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users access own program versions"    ON program_versions;
DROP POLICY IF EXISTS "users access own program activations" ON program_activations;
DROP POLICY IF EXISTS "users access own planned sessions"    ON planned_sessions;

CREATE POLICY "users access own program versions"
    ON program_versions FOR ALL
    USING (user_id = auth.uid()::text);

CREATE POLICY "users access own program activations"
    ON program_activations FOR ALL
    USING (user_id = auth.uid()::text);

CREATE POLICY "users access own planned sessions"
    ON planned_sessions FOR ALL
    USING (user_id = auth.uid()::text);
