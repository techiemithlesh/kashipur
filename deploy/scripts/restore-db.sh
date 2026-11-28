#!/bin/sh
# Restores the master and consumer databases from pg_dump custom-format files into the
# native host PostgreSQL, with every object owned by the application role.
#
# Usage (as root, from the repository checkout on the VPS):
#   sh deploy/scripts/restore-db.sh /tmp/db_swm_master.sql /tmp/db_swm_consumer.sql
# or from a standalone copy:
#   SWM_DIR=/opt/swm/kashipur sh /root/restore-db.sh /tmp/db_swm_master.sql /tmp/db_swm_consumer.sql
#
# Per database:
#   1. Safety backup of the current database to /var/backups/swm/db/<timestamp>/.
#   2. Restore into a scratch database "<name>_restore" created from template0
#      (template1 may contain stray objects). Extensions are created by postgres first;
#      for the consumer, the postgres_fdw link to the master and its foreign tables are
#      recreated before the data so objects that depend on them restore cleanly.
#   3. Single transaction + exit on first error. The live database is replaced only
#      after a clean restore and an ownership check, so a failure leaves it untouched.
# Credentials come from .env.production; nothing secret is typed on the command line.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo >&2 "Run as root: sh deploy/scripts/restore-db.sh <master-dump> <consumer-dump>"
    exit 1
fi
if [ "$#" -ne 2 ]; then
    echo >&2 "Usage: $0 <master-dump-file> <consumer-dump-file>"
    exit 2
fi

# SWM_DIR lets a copy of this script run against the checkout without changing it.
repository_root=${SWM_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
cd "$repository_root"
env_file=.env.production
if [ ! -f "$env_file" ]; then
    echo >&2 "Missing $env_file in $repository_root"
    exit 1
fi

read_env() {
    awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); value = $0 } END { print value }' "$env_file" \
        | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

master_db=$(read_env DB_DATABASE)
consumer_db=$(read_env DB_CONSUMER_DATABASE)
app_user=$(read_env DB_USERNAME)
app_password=$(read_env DB_PASSWORD)
for value in "$master_db" "$consumer_db" "$app_user" "$app_password"; do
    if [ -z "$value" ]; then
        echo >&2 "DB_DATABASE, DB_CONSUMER_DATABASE, DB_USERNAME and DB_PASSWORD must be set in $env_file"
        exit 1
    fi
done

work_dir=$(mktemp -d /tmp/swm-restore.XXXXXX)
backup_dir=
services_stopped=
finish() {
    status=$?
    rm -rf "$work_dir"
    if [ "$status" -ne 0 ] && [ -n "$services_stopped" ]; then
        echo >&2
        echo >&2 "Restore FAILED. A live database is only replaced after its own restore succeeded."
        echo >&2 "Safety backups: $backup_dir"
        echo >&2 "Application services are stopped; start them with:"
        echo >&2 "  docker compose --env-file $env_file up -d"
    fi
    exit "$status"
}
trap finish EXIT
trap 'exit 130' HUP INT TERM

# postgres must be able to read the dumps; work on private copies.
cp "$1" "$work_dir/master.dump"
cp "$2" "$work_dir/consumer.dump"
chown -R postgres "$work_dir"

as_postgres() { sudo -u postgres "$@"; }
# SQL is always passed on stdin: psql interpolates :'var' and :"var" there, never in -c.
psql_db() { db=$1; shift; as_postgres psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
query() { db=$1; shift; as_postgres psql -X -q -tA -v ON_ERROR_STOP=1 -d "$db" "$@"; }
toc() { pg_restore -l "$1"; }

for dump in "$work_dir/master.dump" "$work_dir/consumer.dump"; do
    if ! toc "$dump" >/dev/null 2>&1; then
        echo >&2 "Not a pg_dump custom-format file: $dump"
        exit 1
    fi
done
# A swapped pair is the easiest mistake to make; only the consumer has foreign tables.
if toc "$work_dir/master.dump" | grep -q ' FOREIGN TABLE '; then
    echo >&2 "The master dump contains foreign tables; the two files look swapped"
    exit 1
fi

echo "Master   : $1 -> $master_db"
echo "Consumer : $2 -> $consumer_db"
echo "Owner    : $app_user"

backup_dir=/var/backups/swm/db/$(date +%Y%m%d-%H%M%S)
install -d -m 700 "$backup_dir"

echo "== Stopping application services"
services_stopped=yes
docker compose --env-file "$env_file" stop backend queue scheduler reverb

# Called without || so that set -e stays active inside: any failing command aborts the script.
restore_database() {
    db=$1
    dump=$2
    fdw_master=$3   # master database for the consumer's postgres_fdw link, or empty
    scratch=${db}_restore
    list=$work_dir/$db.list

    echo "== [$db] safety backup"
    exists=$(echo "SELECT 1 FROM pg_database WHERE datname = :'db'" | query postgres -v db="$db")
    if [ -n "$exists" ]; then
        as_postgres pg_dump -Fc "$db" > "$backup_dir/$db.dump"
        echo "   saved $backup_dir/$db.dump"
    else
        echo "   $db does not exist yet, nothing to back up"
    fi

    echo "== [$db] creating scratch database $scratch"
    as_postgres dropdb --force --if-exists "$scratch"
    as_postgres createdb -T template0 -O "$app_user" "$scratch"
    echo 'ALTER SCHEMA public OWNER TO :"owner"' | psql_db "$scratch" -v owner="$app_user"

    for extension in $(toc "$dump" | awk '$4 == "EXTENSION" { print $6 }' | sort -u); do
        echo "   extension $extension"
        echo 'CREATE EXTENSION IF NOT EXISTS :"ext"' | psql_db "$scratch" -v ext="$extension"
    done

    foreign_tables=$(toc "$dump" | awk '$4 == "FOREIGN" && $5 == "TABLE" { print $7 }' | sort -u | paste -sd, -)
    if [ -n "$foreign_tables" ]; then
        if [ -z "$fdw_master" ]; then
            echo >&2 "$db dump has foreign tables but no FDW target database was given"
            exit 1
        fi
        echo "   postgres_fdw link to $fdw_master"
        # psql quotes the variables itself, so passwords containing quotes are safe.
        psql_db "$scratch" -v owner="$app_user" -v pw="$app_password" -v master="$fdw_master" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER db_system_server FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host '127.0.0.1', port '5432', dbname :'master');
GRANT USAGE ON FOREIGN SERVER db_system_server TO :"owner";
CREATE USER MAPPING FOR :"owner" SERVER db_system_server
    OPTIONS (user :'owner', password :'pw');
SQL
        # Imported as the application role so it owns the foreign tables.
        psql_db "$scratch" -v owner="$app_user" -v tables="$foreign_tables" <<'SQL'
SET ROLE :"owner";
IMPORT FOREIGN SCHEMA public LIMIT TO (:tables) FROM SERVER db_system_server INTO public;
SQL
    fi

    echo "== [$db] restoring data"
    toc "$dump" \
        | grep -vE ' EXTENSION | EVENT TRIGGER | FOREIGN TABLE | FOREIGN DATA WRAPPER | SERVER | USER MAPPING ' \
        > "$list"
    as_postgres pg_restore -d "$scratch" --no-owner --no-privileges --role="$app_user" \
        --single-transaction --exit-on-error -L "$list" "$dump"

    wrong_owner=$(echo "SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tableowner <> :'owner'" \
        | query "$scratch" -v owner="$app_user")
    if [ "$wrong_owner" != "0" ]; then
        echo >&2 "[$db] $wrong_owner tables are not owned by $app_user; live database left unchanged"
        exit 1
    fi
    tables=$(echo "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'" | query "$scratch")
    echo "   $tables tables restored"

    echo "== [$db] replacing live database"
    as_postgres dropdb --force --if-exists "$db"
    echo 'ALTER DATABASE :"from" RENAME TO :"to"' | psql_db postgres -v from="$scratch" -v to="$db"
}

# The master must be in place first: the consumer's foreign tables are imported from it.
restore_database "$master_db" "$work_dir/master.dump" ""
restore_database "$consumer_db" "$work_dir/consumer.dump" "$master_db"

echo "== Verifying the consumer -> master link as $app_user"
first_foreign=$(echo "SELECT foreign_table_name FROM information_schema.foreign_tables ORDER BY 1 LIMIT 1" \
    | query "$consumer_db")
if [ -n "$first_foreign" ]; then
    psql_db "$consumer_db" -v owner="$app_user" -v t="$first_foreign" <<'SQL'
SET ROLE :"owner";
SELECT :'t' AS foreign_table, count(*) AS row_count FROM :"t";
SQL
fi

echo "== Starting application services"
docker compose --env-file "$env_file" up -d
services_stopped=

echo
echo "Restore complete. Safety backups of the previous databases: $backup_dir"
