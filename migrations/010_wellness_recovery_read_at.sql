-- When the stored recovery time was read.
--
-- Recovery time counts down, and readiness caps its score at 100 − the hours
-- still left (api._score_watch_recovery). The row's read_at is the newest
-- post's time, and the same-day merge keeps the older recovery hours when a
-- newer post carries none, so counting down from read_at reported too little
-- recovery left. recovery_read_at is the time of the post the stored
-- recovery_time_h came from; src/wellness_store.upsert changes the two together.
--
-- Run: python run_migration.py 010_wellness_recovery_read_at
-- Additive: one nullable column. src/wellness_store.py also adds it lazily.
-- Rows written before it have NULL, and readiness falls back to read_at.

ALTER TABLE daily_wellness ADD COLUMN IF NOT EXISTS recovery_read_at TIMESTAMPTZ;
