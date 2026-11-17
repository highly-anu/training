-- A build of an athlete's own method (docs/roadmap.md item 21, step 21.2).
--
-- An athlete describes a method and a model writes the package: minutes of
-- work, which a request cannot hold and a deploy must not lose. Each build is
-- a row; one worker thread per process claims it, saves the draft and the
-- transcript after every turn, and a row whose worker died is claimed again
-- (src/build_store.py, src/build_worker.py).
--
-- request       what was asked: description, answers (days, minutes, level,
--               equipment), pasted text, whether the web may be searched,
--               revise {packageId, note}
-- status        queued | running | done | failed | cancelled
-- draft_files   the package as written so far, {path: yaml text}
-- transcript    the model conversation so far (what a resume continues from)
-- progress      {stage, detail, turns, checks, problems} — what the clients poll
-- result        when done: {packageId, revision, name, summary}
-- error         when failed: {code, message}
-- usage         tokens and searches spent
-- attempts      how many times a worker claimed it
-- heartbeat_at  the worker's last sign of life: a running row older than the
--               lease is claimed again
--
-- Run (local): python run_migration.py 014_package_builds
-- Run (production): scripts/backup_prod.sh first, then
--   psql "$(grep '^DATABASE_URL=' .env | cut -d= -f2-)" -v ON_ERROR_STOP=1 -f migrations/014_package_builds.sql
-- Additive: one new table. src/build_store.py also creates it lazily, with row
-- security on and no policy (deny-by-default) — the policy below is what lets
-- an athlete read their own rows through PostgREST. Account deletion empties
-- it like every public table with a user_id (src/account.py).

CREATE TABLE IF NOT EXISTS package_builds (
    id               TEXT        PRIMARY KEY,
    user_id          TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'queued',
    request          JSONB       NOT NULL,
    draft_files      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    transcript       JSONB       NOT NULL DEFAULT '[]'::jsonb,
    progress         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    result           JSONB,
    error            JSONB,
    usage            JSONB       NOT NULL DEFAULT '{}'::jsonb,
    attempts         INTEGER     NOT NULL DEFAULT 0,
    cancel_requested BOOLEAN     NOT NULL DEFAULT FALSE,
    heartbeat_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_package_builds_user_created ON package_builds (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_package_builds_open ON package_builds (created_at) WHERE status IN ('queued', 'running');

ALTER TABLE package_builds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users read own builds" ON package_builds;

CREATE POLICY "users read own builds"
    ON package_builds FOR SELECT
    USING (user_id = auth.uid()::text);
