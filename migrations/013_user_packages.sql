-- An athlete's own packages (docs/roadmap.md item 20, step 20.5).
--
-- A package written at runtime — by the LLM package builder — cannot live
-- where the shipped ones do: the image's disk is lost on every deploy. It is
-- kept here as a file map and laid out as a folder per process for the loader
-- (src/package_store.py: loader.overlay), visible to its owner only.
--
-- files       {"philosophy.yaml": "<yaml text>", "frameworks/<id>.yaml": …} —
--             text, capped by the store (200 files, 512 KB)
-- revision    counts installs of this package id; the athlete's overlay
--             directory is named from every (package_id, revision) they have
-- status      installed | quarantined (it stopped passing the gates after an
--             engine change; problems says why)
-- engine_rev  a digest of the schemas and the commons it was checked against
-- deleted_at  a removed package keeps its row and is no longer laid out
--
-- Run (local): python run_migration.py 013_user_packages
-- Run (production): scripts/backup_prod.sh first, then
--   psql "$(grep '^DATABASE_URL=' .env | cut -d= -f2-)" -v ON_ERROR_STOP=1 -f migrations/013_user_packages.sql
-- Additive: one new table. src/package_store.py also creates it lazily, with
-- row security on and no policy (deny-by-default) — the policy below is what
-- lets an athlete read their own rows through PostgREST. Account deletion
-- empties it like every public table with a user_id (src/account.py).

CREATE TABLE IF NOT EXISTS user_packages (
    user_id     TEXT        NOT NULL,
    package_id  TEXT        NOT NULL,
    revision    INTEGER     NOT NULL DEFAULT 1,
    name        TEXT,
    files       JSONB       NOT NULL,
    status      TEXT        NOT NULL DEFAULT 'installed',
    problems    JSONB,
    engine_rev  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ,
    PRIMARY KEY (user_id, package_id)
);

ALTER TABLE user_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users access own packages" ON user_packages;

CREATE POLICY "users access own packages"
    ON user_packages FOR ALL
    USING (user_id = auth.uid()::text);
