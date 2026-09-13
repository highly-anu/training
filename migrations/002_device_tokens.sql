-- Device tokens table
-- Backs the Garmin (and future) watch-companion pairing flow. A watch mints a
-- pending pairing (short code + long-lived device token) with no auth; the user,
-- while signed in on web/phone, claims the code, binding the token to their
-- user_id. Thereafter the watch authenticates with `Authorization: Bearer <token>`.
--
-- Accessed only by the backend service role (which bypasses RLS); ownership is
-- enforced in application code (src/device_store.py + src/auth.py), because the
-- initial /devices/pair insert is intentionally unauthenticated.
CREATE TABLE IF NOT EXISTS device_tokens (
    device_token TEXT PRIMARY KEY,
    pairing_code TEXT,
    user_id      TEXT,                       -- NULL until the code is claimed
    claimed      BOOLEAN NOT NULL DEFAULT FALSE,
    device_name  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    claimed_at   TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ
);

-- Fast code lookup while a pairing is still pending (codes are single-use + short-lived).
CREATE INDEX IF NOT EXISTS idx_device_tokens_pairing_code
    ON device_tokens (pairing_code) WHERE claimed = FALSE;

-- List / revoke a user's devices.
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
    ON device_tokens (user_id);
