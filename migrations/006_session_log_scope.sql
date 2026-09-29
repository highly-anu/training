-- Scope a session log to the program it was logged under.
--
-- session_logs' primary key was (session_key, user_id), and session_key is
-- program-relative — '3-Monday-0' names a different session in every plan the
-- athlete has ever had. So a log written for week 3 Monday of a NEW program
-- collided with the old program's row, and health_store.upsert_session_log does
--
--     exercises    = session_logs.exercises || EXCLUDED.exercises,
--     completed_at = GREATEST(EXCLUDED.completed_at, session_logs.completed_at)
--
-- which means it did not merely overwrite: it MERGED the old block's set data
-- into the new one and carried its completion timestamp forward, so a session
-- the athlete had never done could render as already complete with somebody
-- else's numbers in it. Silent cross-program corruption, not just ambiguity.
--
-- The fix is a generated key: session_uid where we have one, the old
-- session_key where we do not.
--
--   * Existing rows all have session_uid IS NULL, so their log_key is exactly
--     the session_key that was already their primary key — they stay valid and
--     uniqueness cannot be violated by this migration.
--   * New rows carry a session_uid and are therefore scoped to one program
--     version.
--   * Clients that only know how to send a session_key keep working; the server
--     resolves the uid for them (health_store._log_session_uid).
--
-- Run AFTER 005 and after scripts/backfill_program_history.py:
--   python run_migration.py 006_session_log_scope

ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS session_uid TEXT;

-- STORED, not VIRTUAL: it is a key, so it has to be indexable. Postgres
-- recomputes it whenever session_uid changes, which is what lets the backfill
-- re-scope a legacy row by setting one column.
ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS log_key TEXT
    GENERATED ALWAYS AS (COALESCE(session_uid, session_key)) STORED;

ALTER TABLE session_logs DROP CONSTRAINT IF EXISTS session_logs_pkey;
ALTER TABLE session_logs ADD  CONSTRAINT session_logs_pkey PRIMARY KEY (user_id, log_key);

-- Readers still look logs up by the program-relative key, and it is no longer
-- unique, so it needs its own index.
CREATE INDEX IF NOT EXISTS idx_session_logs_key ON session_logs (user_id, session_key);
