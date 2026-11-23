#!/usr/bin/env bash
# Nightly PostgreSQL backups (custom format, restorable with pg_restore or pgAdmin).
# Cron (as deploy):  30 2 * * * /opt/swm/deploy/scripts/backup-db.sh >> /opt/swm/backups/backup.log 2>&1
# Keep an off-server copy too: pull them to your machine (scp) or sync to object storage.
set -euo pipefail

cd "$(dirname "$0")/../.."
source deploy/scripts/lib.sh "$@"

BACKUP_DIR="$(env_value BACKUP_DIR)"; BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"
RETENTION="$(env_value BACKUP_RETENTION_DAYS)"; RETENTION="${RETENTION:-14}"
STAMP="$(date +%Y-%m-%d_%H%M)"
TARGET="$BACKUP_DIR/$STAMP"

umask 077
mkdir -p "$TARGET"

for var in DB_DATABASE DB_CONSUMER_DATABASE; do
  db="$(env_value "$var")"
  echo "$(date -Is) dumping $db"
  compose exec -T db sh -c "pg_dump -U \"\$POSTGRES_USER\" -d '$db' -Fc --no-owner --no-acl" > "$TARGET/$db.dump"
  # Fail loudly on an empty/corrupt dump instead of silently keeping junk.
  compose exec -T db pg_restore -l < "$TARGET/$db.dump" > /dev/null
done

# Uploaded files (photos, documents) live in Docker volumes; back them up with the DB.
docker run --rm \
  -v swm_public_uploads:/public:ro -v swm_private_uploads:/private:ro \
  alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f tar -C / -czf - public private > "$TARGET/uploads.tar.gz"

sha256sum "$TARGET"/* > "$TARGET/SHA256SUMS"
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+$RETENTION" -exec rm -rf {} +
echo "$(date -Is) backup ok: $TARGET ($(du -sh "$TARGET" | cut -f1))"
