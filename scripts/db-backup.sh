#!/bin/sh
# Back up the CollectiveAccess database and application files.
#
# Run it from a scheduled job on the host (e.g. cron, daily at 02:17). It
# lives in, and is run from, the folder holding compose.yaml and .env:
#
#   <CA_APPDATA>/stack/scripts/db-backup.sh
#
# What it writes, under CA_BACKUPS (from .env):
#
#   database/collectiveaccess_YYYY-MM-DD_HHMMSS.sql         full SQL dump
#   database/collectiveaccess_YYYY-MM-DD_HHMMSS.sql.sha256  its checksum
#   application/stack/    latest copy of compose.yaml, .env and scripts
#   application/config/   latest copy of setup.php and config overrides
#
# Dumps are plain .sql so they can be opened, searched or restored directly.
# On storage with transparent compression they take a fraction of their apparent size on disk.
#
# Old dumps are NOT deleted unless KEEP_DAYS is set (e.g. KEEP_DAYS=90).
# Snapshots of the backup storage keep history of the application/ copy.
set -eu

STACK_DIR="${STACK_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
KEEP_DAYS="${KEEP_DAYS:-}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

cd "$STACK_DIR"

# Read a single value from .env without executing it.
env_get() {
    sed -n "s/^$1=//p" .env | tail -n 1 | sed 's/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}

CA_APPDATA="$(env_get CA_APPDATA)"
CA_BACKUPS="$(env_get CA_BACKUPS)"
: "${CA_APPDATA:?CA_APPDATA is not set in .env}"
: "${CA_BACKUPS:?CA_BACKUPS is not set in .env}"

log() { echo "[db-backup] $*"; }

# --- 1. Database dump ----------------------------------------------------------
# Runs inside the db container, which has the dump tool and the password, and
# writes to /backups (= ${CA_BACKUPS}/database on the host).
#   --single-transaction  consistent snapshot without stopping CollectiveAccess
#   --routines/--triggers/--events  include stored database logic, not just tables
log "Dumping database"
docker compose exec -T db bash -c '
    set -euo pipefail
    out="/backups/collectiveaccess_'"$STAMP"'.sql"
    MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump \
        --user=root \
        --single-transaction --quick \
        --routines --triggers --events \
        --set-gtid-purged=OFF \
        --default-character-set=utf8mb4 \
        "$MYSQL_DATABASE" > "$out.partial"
    mv "$out.partial" "$out"
    cd /backups && sha256sum "$(basename "$out")" > "$(basename "$out").sha256"
    echo "[db-backup] Wrote $out ($(du -h "$out" | cut -f1))"
'

# --- 2. Application copy -------------------------------------------------------
# Mirror the stack folder (compose.yaml, .env, scripts) and config folder.
# .env contains passwords, so the copy is readable by root only.
log "Copying application files"
mkdir -p "$CA_BACKUPS/application"
chmod 700 "$CA_BACKUPS/application"

copy_dir() {
    src="$1"; dest="$2"
    [ -d "$src" ] || { log "Skipping $src (not found)"; return 0; }
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src/" "$dest/"
    else
        rm -rf "$dest" && cp -a "$src" "$dest"
    fi
}
copy_dir "$STACK_DIR"           "$CA_BACKUPS/application/stack"
copy_dir "$CA_APPDATA/config"   "$CA_BACKUPS/application/config"

# --- 3. Optional pruning -------------------------------------------------------
if [ -n "$KEEP_DAYS" ]; then
    log "Removing dumps older than $KEEP_DAYS days"
    find "$CA_BACKUPS/database" -name 'collectiveaccess_*.sql*' -mtime +"$KEEP_DAYS" -delete
fi

log "Done"
