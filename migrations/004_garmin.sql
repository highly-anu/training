-- Garmin Connect integration + a shared OAuth state store.
--
-- Run: python run_migration.py 004_garmin

-- ---------------------------------------------------------------------------
-- OAuth CSRF state (replaces oauth.py's local SQLite file)
-- ---------------------------------------------------------------------------
-- Strava's `state` lives in data/oauth_state.db, on fly.io's ephemeral disk: a
-- machine restart mid-flow loses it and the callback fails with "possible
-- CSRF". Garmin additionally needs to carry a PKCE code_verifier, which is a
-- secret the callback must recover server-side and so cannot ride in a cookie.
CREATE TABLE IF NOT EXISTS oauth_state (
    state         TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL,
    provider      TEXT NOT NULL,          -- 'strava' | 'garmin'
    code_verifier TEXT,                   -- PKCE; NULL for Strava
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_oauth_state_created_at ON oauth_state (created_at);


-- ---------------------------------------------------------------------------
-- Garmin tokens
-- ---------------------------------------------------------------------------
-- Columns are kept generic so the store doesn't care whether we end up on
-- OAuth 2.0 + PKCE (current Connect Developer Program) or the legacy OAuth 1.0a
-- Health API — only src/garmin_connect.py knows which.
--
-- garmin_user_id is the load-bearing one: webhook payloads identify the athlete
-- by Garmin's id, and it is the only way back to our user_id.
CREATE TABLE IF NOT EXISTS garmin_tokens (
    user_id                  TEXT PRIMARY KEY,
    oauth_version            SMALLINT NOT NULL DEFAULT 2,
    access_token             TEXT NOT NULL,
    refresh_token            TEXT,
    token_secret             TEXT,          -- OAuth 1.0a only
    expires_at               BIGINT,        -- unix seconds; NULL = non-expiring
    refresh_token_expires_at BIGINT,
    garmin_user_id           TEXT UNIQUE,
    scope                    TEXT,
    athlete_name             TEXT,
    connected_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_sync_at             TIMESTAMPTZ,
    last_webhook_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_garmin_tokens_garmin_user
    ON garmin_tokens (garmin_user_id);


-- ---------------------------------------------------------------------------
-- Webhook event queue
-- ---------------------------------------------------------------------------
-- Garmin expects a prompt 200 and will disable an endpoint that keeps erroring,
-- and gunicorn runs a single sync worker (see Dockerfile) so any network call
-- made inside the request handler blocks the entire API. The handler therefore
-- writes the payload here and returns; a worker thread drains it. The row is
-- what makes that durable across a machine restart.
CREATE TABLE IF NOT EXISTS garmin_webhook_events (
    id           BIGSERIAL PRIMARY KEY,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type   TEXT NOT NULL,            -- 'activities' | 'deregistration' | 'permission_change'
    payload      JSONB NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending',  -- pending|processing|done|failed|ignored
    attempts     INTEGER NOT NULL DEFAULT 0,
    last_error   TEXT,
    processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_garmin_events_pending
    ON garmin_webhook_events (status, received_at)
    WHERE status IN ('pending', 'failed');


-- ---------------------------------------------------------------------------
-- Imported activity ledger
-- ---------------------------------------------------------------------------
-- Idempotency guard: a redelivered ping for an activity we already have
-- short-circuits before any network fetch.
CREATE TABLE IF NOT EXISTS garmin_activities (
    garmin_user_id TEXT NOT NULL,
    summary_id     TEXT NOT NULL,
    user_id        TEXT NOT NULL,
    workout_id     TEXT,
    imported_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (garmin_user_id, summary_id)
);
