#!/usr/bin/env bash
# Runs the Supabase migrations and pgTAP tests against a throwaway local Postgres, without Docker.
# Requires Postgres 15+ server binaries and pgTAP (Ubuntu: postgresql-16 postgresql-16-pgtap).
# CI uses the Supabase CLI instead (see .github/workflows/supabase.yml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_BIN="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)}"
WORK="$(mktemp -d)"
PORT="${PORT:-55432}"

# initdb and pg_ctl refuse to run as root; use the postgres user when needed.
RUN=()
if [ "$(id -u)" = "0" ]; then
  chown -R postgres "$WORK"
  RUN=(runuser -u postgres --)
fi

cleanup() {
  "${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN[@]}" "$PG_BIN/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
"${RUN[@]}" "$PG_BIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK" -l "$WORK/log" start >/dev/null

PSQL=(psql -h "$WORK" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -f "$ROOT/scripts/supabase_local_stub.sql"
for migration in "$ROOT"/supabase/migrations/*.sql; do
  echo "migrate: $(basename "$migration")"
  "${PSQL[@]}" -f "$migration"
done
"${PSQL[@]}" -c "create extension if not exists pgtap"

status=0
for test in "$ROOT"/supabase/tests/*.sql; do
  echo "test: $(basename "$test")"
  output="$("${PSQL[@]}" -X -t -A -f "$test" 2>&1)" || status=1
  echo "$output"
  if grep -q "^not ok" <<<"$output" || grep -q "Looks like you" <<<"$output"; then
    status=1
  fi
done

if [ "$status" = "0" ]; then echo "ALL DB TESTS PASSED"; else echo "DB TESTS FAILED"; fi
exit "$status"
