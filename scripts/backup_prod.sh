#!/usr/bin/env bash
# Dump the production database and prove the dump restores.
#
# A backup nobody has restored is a hope, not a backup — so this script does
# both: pg_dump (custom format) into backups/, pg_restore into a throwaway
# local database, and a table-by-table row-count comparison against prod.
# It exits non-zero on any mismatch. Run it before anything that touches
# production structure (migrations, backfills); docs/program-history-release.md
# calls it from its pre-flight.
#
# Reads DATABASE_URL from .env — the production-shaped file, deliberately not
# .env.local, which points at the local training_test database. Requires a
# pg_dump at least as new as the server (Supabase runs PG 17; Homebrew's
# postgresql@14 client refuses it): brew install libpq.
#
#   scripts/backup_prod.sh              # dump + restore-test
#   KEEP_RESTORE=1 scripts/backup_prod.sh   # leave training_restore_check in place
#
# backups/ holds personal health data. It is gitignored and dockerignored;
# keep it that way.
set -euo pipefail

cd "$(dirname "$0")/.."

PG_BIN="${PG_BIN:-/opt/homebrew/opt/libpq/bin}"
PGDSN="${PROD_DATABASE_URL:-$(grep '^DATABASE_URL=' .env | cut -d= -f2-)}"
[ -n "$PGDSN" ] || { echo "no DATABASE_URL in .env" >&2; exit 2; }

mkdir -p backups
OUT="backups/prod-$(date +%Y%m%d-%H%M).dump"

echo "dumping → $OUT"
"$PG_BIN/pg_dump" -Fc --no-owner --no-privileges --schema=public "$PGDSN" -f "$OUT"
ls -la "$OUT"

SCRATCH=training_restore_check
echo "restoring into local $SCRATCH"
dropdb --if-exists "$SCRATCH"
createdb "$SCRATCH"
# Expected on a local server: SET transaction_timeout (a PG17-only GUC), CREATE
# SCHEMA public (already there), and the RLS policies that call auth.uid() —
# there is no Supabase `auth` schema locally, so those policies do not restore
# and the data does. Anything else is a real error and fails the run.
restore_log=$(mktemp)
"$PG_BIN/pg_restore" -d "$SCRATCH" --no-owner --no-privileges "$OUT" >"$restore_log" 2>&1 || true
if grep 'error' "$restore_log" \
     | grep -v 'transaction_timeout\|schema "public" already exists\|schema "auth" does not exist' \
     | grep -q .; then
  grep -v '^Command was:' "$restore_log" >&2
  echo "restore reported unexpected errors above" >&2
  rm -f "$restore_log"; exit 1
fi
rm -f "$restore_log"

echo "row counts  prod | restored"
status=0
for t in $(psql "$PGDSN" -Atc "select tablename from pg_tables where schemaname='public' order by 1"); do
  a=$(psql "$PGDSN" -Atc "select count(*) from $t")
  b=$(psql "$SCRATCH" -Atc "select count(*) from $t" 2>/dev/null || echo missing)
  if [ "$a" = "$b" ]; then mark=ok; else mark=MISMATCH; status=1; fi
  printf "  %-28s %6s | %6s  %s\n" "$t" "$a" "$b" "$mark"
done

[ -n "${KEEP_RESTORE:-}" ] || dropdb "$SCRATCH"

if [ "$status" -ne 0 ]; then
  echo "backup NOT verified — do not proceed" >&2
  exit 1
fi
echo "backup verified: $OUT"
