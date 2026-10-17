-- Results a logged session suggests, waiting for the athlete to confirm them.
--
-- A test session's scored slot (src/standard_tests.py) produces a number —
-- a 2 km row's time, Cindy's rounds, reps in six minutes — and a single on a
-- lift a ×BW standard is read from can beat the current result. Each becomes
-- a suggestion here when the session log arrives (src/standard_results.py),
-- and a result in performance_logs only when the athlete confirms it.
--
-- A pending suggestion is never a result. workout_match_suggestions is
-- separate from workout_matches for the same reason: a dozen readers took
-- "a match row that isn't rejected" as matched.
--
-- log_key      the session log it came from: its session_uid, else its legacy
--              key; a best effort from an imported workout has neither
-- origin       test_slot | derived_single | best_effort
-- source       what the result's source will be (session | garmin | apple_watch | workout)
-- value/input  in the standard's unit, and what was logged ({"seconds": 298},
--              {"rounds": 20, "reps": 7}, {"kg": 140, "reps": 1, ...})
-- logged_on    the athlete's day the session was done (computed in Python)
-- status       pending | confirmed | dismissed; a re-logged value reopens a
--              confirmed one (to correct its result) and never revives a
--              dismissed one
--
-- Run: python run_migration.py 012_standard_suggestions
-- Additive: one new table. src/standards_store.py also creates it lazily,
-- with row security on and no policy (deny-by-default) — the policy below is
-- what lets an athlete read their own rows through PostgREST.

CREATE TABLE IF NOT EXISTS standard_result_suggestions (
    id                 BIGSERIAL   PRIMARY KEY,
    user_id            TEXT        NOT NULL,
    benchmark_id       TEXT        NOT NULL,
    session_uid        TEXT,
    session_key        TEXT,
    workout_id         TEXT,
    log_key            TEXT        GENERATED ALWAYS AS
                           (COALESCE(session_uid, session_key, 'workout:' || workout_id)) STORED,
    exercise_id        TEXT,
    slot_role          TEXT,
    origin             TEXT        NOT NULL,
    source             TEXT        NOT NULL DEFAULT 'session',
    value              REAL        NOT NULL,
    input              JSONB,
    logged_on          DATE,
    status             TEXT        NOT NULL DEFAULT 'pending',
    performance_log_id BIGINT,
    decided_via        TEXT,
    decided_at         TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, benchmark_id, log_key)
);

CREATE INDEX IF NOT EXISTS idx_standard_suggestions_user_status
    ON standard_result_suggestions (user_id, status);

ALTER TABLE standard_result_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users access own standard suggestions" ON standard_result_suggestions;

CREATE POLICY "users access own standard suggestions"
    ON standard_result_suggestions FOR ALL
    USING (user_id = auth.uid()::text);
