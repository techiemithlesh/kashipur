#!/usr/bin/env bash
# Run after restoring db_swm_master / db_swm_consumer (pgAdmin, pg_restore, clone script).
#  1. Recreates the consumer -> master postgres_fdw foreign tables (a non-superuser restore skips them).
#  2. Baselines Laravel's migrations table, then applies newer migrations.
#  3. Clears Laravel caches so nothing stale survives the restore.
# Usage (from the repo root): deploy/scripts/db-post-restore.sh [--env-file .env.production]
set -euo pipefail

cd "$(dirname "$0")/../.."
source deploy/scripts/lib.sh "$@"

compose cp docker/postgres/fdw/consumer-fdw.sql db:/tmp/consumer-fdw.sql
compose cp docker/postgres/baseline-migrations.sql db:/tmp/baseline-migrations.sql

# shellcheck disable=SC2016 # expanded inside the container
compose exec -T db sh -c '
  set -e
  psql -q -U "$POSTGRES_USER" -d "$DB_CONSUMER_DATABASE" -f /tmp/consumer-fdw.sql
  psql -q -U "$POSTGRES_USER" -d "$DB_DATABASE" -f /tmp/baseline-migrations.sql
  rm -f /tmp/consumer-fdw.sql /tmp/baseline-migrations.sql
'

compose exec -T backend php artisan migrate --force --no-interaction
compose exec -T backend php artisan optimize:clear >/dev/null
compose restart backend queue reverb >/dev/null
echo "Post-restore steps complete."
