-- Daily wellness read on the wrist by the Connect IQ app.
--
-- Garmin's Developer Program is closed to personal applications, so the watch
-- app reads what the Connect IQ SDK exposes — resting heart rate, heart-rate
-- and Body Battery history, recovery time — and posts one row per local day
-- with its paired ciqdev_ token (POST /api/health/wellness).
--
-- A side table, not daily_bio: health_store.upsert_daily_bio overwrites a day
-- wholesale and swallows every error, so a watch post into daily_bio would
-- wipe the Apple Health relay's sleep and HRV for that date. The two series
-- are merged only for scoring, in src/wellness.merge_for_scoring, which takes
-- resting HR from one source and never mixes them.
--
-- No HRV columns: nightly HRV, sleep and training readiness are not readable
-- through the open SDK.
--
-- Run: python run_migration.py 009_wellness
-- Additive: one new table. src/wellness_store.py also creates it lazily,
-- without the policy below.

CREATE TABLE IF NOT EXISTS daily_wellness (
    user_id              TEXT        NOT NULL,
    date                 DATE        NOT NULL,   -- the athlete's local day
    source               TEXT        NOT NULL DEFAULT 'garmin_ciq',
    resting_hr           INTEGER,                -- UserProfile.restingHeartRate
    resting_hr_7d_avg    INTEGER,                -- UserProfile.averageRestingHeartRate
    hr_min               INTEGER,                -- lowest SensorHistory sample (6 h on a fenix 9 Pro)
    hr_low5              REAL,                   -- mean of the lowest five samples
    hr_samples           INTEGER,
    body_battery_max     INTEGER,
    body_battery_min     INTEGER,
    body_battery_latest  INTEGER,
    recovery_time_h      INTEGER,                -- ActivityMonitor.Info.timeToRecovery
    vo2max               INTEGER,
    stress               INTEGER,
    part_number          TEXT,
    firmware             TEXT,
    read_at              TIMESTAMPTZ,            -- when the watch took the reading
    received_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, date, source)
);

ALTER TABLE daily_wellness ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users access own wellness" ON daily_wellness;
CREATE POLICY "users access own wellness"
    ON daily_wellness FOR ALL
    USING (user_id = auth.uid()::text);
