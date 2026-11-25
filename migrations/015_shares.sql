-- Shared links (docs/roadmap.md item 25).
--
-- An athlete shares a method, their program or one session as a link
-- (https://<web host>/s/<token>). The row holds what the link shows — a
-- snapshot taken when it was shared, so the link reads the same after the
-- sharer edits or removes what it came from (src/share_store.py,
-- src/sharing.py).
--
-- token       the link's secret: 128 random bits, URL-safe
-- user_id     the sharer (so account deletion empties their links)
-- kind        package | program | session
-- title       what the sharer's list and the page's header say
-- payload     package: its files (and those of the sharer's own packages it
--             borrows from) and the Explore document built in the sharer's
--             view; program: the recipe, a summary and the packages it needs;
--             session: the session as planned, with its blocks
-- revoked_at  a revoked link answers 404 and keeps its row
--
-- Run (local): python run_migration.py 015_shares
-- Run (production): scripts/backup_prod.sh first, then
--   psql "$(grep '^DATABASE_URL=' .env | cut -d= -f2-)" -v ON_ERROR_STOP=1 -f migrations/015_shares.sql
-- Additive: one new table. src/share_store.py also creates it lazily, with
-- row security on and no policy (deny-by-default) — the policy below lets an
-- athlete read their own rows through PostgREST. The public page reads through
-- the API's own connection, never PostgREST. Account deletion empties it like
-- every public table with a user_id (src/account.py).

CREATE TABLE IF NOT EXISTS shares (
    token       TEXT        PRIMARY KEY,
    user_id     TEXT        NOT NULL,
    kind        TEXT        NOT NULL,
    title       TEXT,
    payload     JSONB       NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS shares_user_idx ON shares (user_id) WHERE revoked_at IS NULL;

ALTER TABLE shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users access own shares" ON shares;

CREATE POLICY "users access own shares"
    ON shares FOR ALL
    USING (user_id = auth.uid()::text);
