# Program history — release runbook

Everything on the `feat/program-history` branch is finished and tested, but
**nothing has been run against production**. The migrations, the backfill and
the deploy are deliberately separable so this can go out in one pass or in two.

Written to be picked up cold. If you are reading this months later, start at
*What this changes* and then follow *The release* in order.

---

## What this changes

`user_programs` holds one row per athlete and `save_user_program` upserts it, so
generating a program destroyed the previous one. A planned session's only
identity was the program-relative string `"{week_number}-{DayName}-{idx}"`,
which references nothing. Three consequences:

1. a workout dated inside a finished block had no candidates and was dropped on
   import — permanently, with no way to match it afterwards;
2. a stored match silently re-pointed at whatever now occupied that (week, day,
   index), so a replaced block's Zone 2 run displayed as the new block's squat
   day, compliance score and all;
3. `session_logs`, keyed on the same string, **merged** one block's set data
   into another's row — `exercises || EXCLUDED.exercises` and
   `completed_at = GREATEST(...)` — so a session never performed could render
   complete with someone else's numbers in it.

The fix archives every program version with the dates it was in force, and
gives every planned session a durable id. See `## Program History` in
`CLAUDE.md` for the design and the invariants; this file is only about shipping
it.

---

## Pre-flight

```bash
# How long will 006 hold its lock? It rewrites this table.
psql "$DATABASE_URL" -c "SELECT count(*) AS rows,
  pg_size_pretty(pg_total_relation_size('session_logs')) AS size FROM session_logs;"

# Sanity: how many matches and logs are there to attribute?
psql "$DATABASE_URL" -c "SELECT
  (SELECT count(*) FROM workout_matches) AS matches,
  (SELECT count(*) FROM session_logs)    AS logs,
  (SELECT count(*) FROM user_programs)   AS programs;"
```

**Take a snapshot — and prove it restores:**

```bash
scripts/backup_prod.sh        # pg_dump 17 → backups/, restore into a scratch
                              # local DB, row counts compared table by table
```

It reads the production `DATABASE_URL` from `.env` (not `.env.local`, which
points local dev at the local database) and exits non-zero on any mismatch.
`backups/` is gitignored and dockerignored. Take the Supabase dashboard backup
too if the project's tier offers one; the dump is the one we rely on.

**Two things the CI setup changes about the order below.**
`.github/workflows/deploy-api.yml` deploys to Fly on every push to `master`
that touches `api.py`, `src/` or `migrations/` — so *merging the PR is step 2*.
Run step 1 from the branch checkout before merging. And because `api.py` and
`run_migration.py` now layer `.env.local` over `.env`, rename `.env.local`
aside (`mv .env.local .env.local.off`) for the duration of the prod steps, or
`run_migration.py` will migrate the local database instead. Restore it after.

What the snapshot is actually for is explained under *Risk* below — it is not
migration failure.

---

## The release

### 1. Migration 005 — additive

```bash
python run_migration.py 005_program_history
```

Creates `program_versions`, `program_activations`, `planned_sessions`, and adds
a nullable `session_uid` column to `workout_matches`,
`workout_match_suggestions` and `session_logs`. Nothing existing is modified.

**Run this before deploying the code.** `src/program_history._ensure_tables` is
a fallback for a deploy that gets ahead of its migration: it creates the tables
with row security enabled but *no policy* (deny-by-default — a test database has
no `auth` schema to write one against). The migration is what adds the real
per-user policies, and these tables live in `public`, which Supabase exposes
through PostgREST.

Verify:

```sql
SELECT tablename, rowsecurity FROM pg_tables
 WHERE tablename IN ('program_versions','program_activations','planned_sessions');
SELECT tablename, policyname FROM pg_policies
 WHERE tablename IN ('program_versions','program_activations','planned_sessions');
```

Three tables, `rowsecurity` true, one policy each.

### 2. Deploy the code

Ordinary deploy. From here `GET /api/user/program` archives the stored program
on first read, so history begins accumulating immediately — the backfill in
step 3 is then partly redundant but still worth running for the attribution.

### 3. Backfill

```bash
python scripts/backfill_program_history.py --dry-run     # read the counts
python scripts/backfill_program_history.py               # then for real
```

Three phases: archive each athlete's current program, attribute existing
`workout_matches`, attribute existing `session_logs`. Idempotent and
re-runnable. It writes only to the new tables and the new nullable column.

Attribution is unambiguous-only: a key that matches more than one candidate on
the workout's own date, or none, is left `NULL` and keeps working through the
legacy path.

**Read the final line.** `need merging: N` must be **0** before step 4. A
non-zero count means two log rows resolve to the same planned session —
typically a day-level `3-Monday` and an indexed `3-Monday-0` written by
different screens. They are the only thing that can make 006 fail, and they want
merging by hand:

```sql
-- Which sessions have more than one log row pointing at them:
SELECT user_id, session_uid, count(*)
  FROM session_logs
 WHERE session_uid IS NOT NULL
 GROUP BY user_id, session_uid
HAVING count(*) > 1;

-- Then look at the rows themselves, to see which holds the real set data:
SELECT session_key, completed_at, notes, exercises
  FROM session_logs
 WHERE user_id = :user_id AND session_uid = :session_uid;
```

Keep the row with the real set data, delete the other, re-run the backfill.

### 4. Migration 006 — the session-log key

```bash
python run_migration.py 006_session_log_scope
```

Adds `log_key` as `COALESCE(session_uid, session_key)` and moves the primary key
to `(user_id, log_key)`. This is what stops the cross-program merge described
above. Existing rows all keep their old key, so no client breaks.

Verify:

```sql
SELECT a.attname FROM pg_index i
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
 WHERE i.indrelid = 'session_logs'::regclass AND i.indisprimary;
-- expect: user_id, log_key
```

---

## Risk

**Steps 1 and 3 are additive and reversible.** `ADD COLUMN … TEXT` with no
default is metadata-only in modern Postgres — no table rewrite, no meaningful
lock.

**Step 4 is the only one that touches existing structure**, and two properties
matter:

- It **rewrites `session_logs`** (a `STORED` generated column) under an
  `ACCESS EXCLUSIVE` lock. Duration scales with row count — hence the
  pre-flight check.
- It is **atomic**. `run_migration.py` sends the file as one multi-statement
  query, which Postgres wraps in an implicit transaction. Tested against
  deliberately colliding rows: the whole file rolled back, the old primary key
  survived, no orphan `log_key` column, rows untouched. The failure mode worth
  fearing — primary key dropped, rebuild fails, table left keyless — cannot
  happen.

**So what is the snapshot for?** Not migration failure, which rolls back. It is
for the backfill having attributed a `session_uid` *wrongly*: once 006 is
applied, `log_key` derives from that column, so a wrong uid silently re-homes a
log row. Low probability — the backfill refuses anything ambiguous — but it is a
data-content risk rather than a schema one, and a snapshot is what covers it.

---

## Rollback

| Step | Undo |
|---|---|
| 4 | `ALTER TABLE session_logs DROP CONSTRAINT session_logs_pkey;`<br>`ALTER TABLE session_logs DROP COLUMN log_key;`<br>`ALTER TABLE session_logs ADD CONSTRAINT session_logs_pkey PRIMARY KEY (session_key, user_id);`<br>Only safe while no two rows share a `session_key` per user — true unless new logs have been written since. |
| 3 | `UPDATE workout_matches SET session_uid = NULL;`<br>`UPDATE session_logs SET session_uid = NULL;`<br>`TRUNCATE planned_sessions, program_activations, program_versions;` |
| 2 | Redeploy the previous build. The new columns and tables are ignored by it. |
| 1 | `DROP TABLE planned_sessions, program_activations, program_versions;`<br>`ALTER TABLE workout_matches DROP COLUMN session_uid;` (and the same on `workout_match_suggestions`, `session_logs`) |

Undoing 2 without undoing 1 or 3 is safe and is the cheapest way out if
something looks wrong: the old code neither reads nor writes any of it.

---

## Splitting the release

Steps 1–3 deliver the whole matching and history fix on their own — a workout
dated inside a finished block matches the session that was actually planned, and
progression stops resetting when a program is replaced.

Step 4 only fixes the cross-program log merge. If you want a small blast radius
on day one, defer it: the `session_uid` column it depends on is already
populated by then, so it applies cleanly whenever you come back to it.

---

## What this cannot do

**History starts at deploy.** Programs already overwritten by
`ON CONFLICT … DO UPDATE` are gone. The one plan that can still be saved is the
currently stored one, which is why archiving happens on read as well as on
write.

The backfill deliberately does **not** infer a start date from
`(workout.date, session_key)`. That arithmetic is wrong by
`(week_number − 1 − week_index) × 7` days — fifteen weeks for a program numbered
from its absolute week — and undefined when a week number repeats. It would
fabricate plans that never existed.

One inherited bug is untouched: `src/fit_import.py` derives a workout's date
from a UTC-forced start time, so an evening workout west of UTC is already dated
a day late, and no user timezone is stored anywhere. `resolve_session` has a
±1-day widening fallback used only for attributing an *existing* match for
display — never for scoring, because the matcher's golden fixtures pin that
behaviour.

---

## Verifying it worked

```bash
# Backend
.venv/bin/python test_program_history.py        # hashing, flattening, intervals (no DB)
.venv/bin/python test_program_history_sql.py    # the timeline + the acceptance test
.venv/bin/python test_workout_matcher.py        # the cross-language parity contract
cd frontend && npx vitest run                   # incl. the TS half of that contract
```

On production, after step 3:

```sql
-- Every athlete should have at least one activation, the newest still open.
SELECT user_id, count(*) AS activations,
       count(*) FILTER (WHERE effective_to IS NULL) AS open
  FROM program_activations GROUP BY user_id;

-- Intervals must be disjoint: this should return no rows.
SELECT a.user_id, a.id, b.id FROM program_activations a
  JOIN program_activations b
    ON a.user_id = b.user_id AND a.id < b.id
   AND a.effective_from < COALESCE(b.effective_to, 'infinity'::date)
   AND b.effective_from < COALESCE(a.effective_to, 'infinity'::date);
```

Then in the app: Program → History (web: `/program/history`) lists every block
with its dates, weeks trained, and matched/logged counts.

---

## Known gap

The Xcode project has **no test target** — `xcodebuild test` reports the scheme
is not configured for the test action, and the three files in
`ios/TrainingCompanionTests/` (two of which predate this work) never execute.
`ProgramHistoryFormatTests.swift` is written and ready for whenever a target is
added; until then the iOS screens are verified by running the simulator, per
`CLAUDE.md`.
