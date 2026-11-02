#!/bin/sh
# Container entrypoint for CollectiveAccess Providence.
#
#  1. Optionally remaps the www-data user to the UID/GID that owns the
#     host folders (CA_UID / CA_GID), so mounted folders are writable
#     without loosening their permissions.
#  2. Makes sure the writable state directories exist.
#  3. Waits for the database to accept connections.
#  4. Hands over to the real command (Apache by default).
set -eu

log() { echo "[ca-entrypoint] $*"; }

# --- 1. User remapping -------------------------------------------------------
CA_UID="${CA_UID:-}"
CA_GID="${CA_GID:-}"

if [ "$(id -u)" = "0" ]; then
    if [ -n "$CA_GID" ] && [ "$(id -g www-data)" != "$CA_GID" ]; then
        log "Setting www-data group id to $CA_GID"
        groupmod -o -g "$CA_GID" www-data
    fi
    if [ -n "$CA_UID" ] && [ "$(id -u www-data)" != "$CA_UID" ]; then
        log "Setting www-data user id to $CA_UID"
        usermod -o -u "$CA_UID" www-data
    fi
fi

# --- 2. Writable directories -------------------------------------------------
# The ca-tmp volume holds Providence's temp folder (ca/), which Providence
# empties on install and on schema updates, plus two upload staging folders
# beside it so they survive that: php-uploads/ (PHP's upload_tmp_dir, see
# php/collectiveaccess.ini) and media-uploads/ (the media uploader, see
# Dockerfile).
STATE_TMP="/var/lib/collectiveaccess/tmp"
TEMP_DIR="${CA_TEMP_DIR:-$STATE_TMP/ca}"
LOG_DIR="${CA_LOG_DIR:-/var/lib/collectiveaccess/log}"
MEDIA_DIR="/var/www/html/media/collectiveaccess"
PURIFIER_DIR="/var/www/html/vendor/ezyang/htmlpurifier/library/HTMLPurifier/DefinitionCache"
FONT_DIR="/var/www/html/app/fonts"

for dir in "$TEMP_DIR" "$STATE_TMP/php-uploads" "$STATE_TMP/media-uploads" "$LOG_DIR"; do
    mkdir -p "$dir"
done

if [ "$(id -u)" = "0" ]; then
    # These are small; always make sure www-data owns them.
    chown -R www-data:www-data "$STATE_TMP" "$TEMP_DIR" "$LOG_DIR" "$PURIFIER_DIR" "$FONT_DIR"
    # The media folder can be huge: only fix the top level, never recurse.
    chown www-data:www-data "$MEDIA_DIR" 2>/dev/null || true
fi

if ! setpriv --reuid=www-data --regid=www-data --init-groups test -w "$MEDIA_DIR" 2>/dev/null; then
    log "WARNING: $MEDIA_DIR is not writable by www-data (uid $(id -u www-data))."
    log "         Check CA_UID/CA_GID match the owner of the media folder."
fi

# --- 3. Wait for the database ------------------------------------------------
if [ "${CA_SKIP_DB_WAIT:-false}" != "true" ]; then
    DB_HOST="${CA_DB_HOST:-db}"
    DB_PORT="${CA_DB_PORT:-3306}"
    TIMEOUT="${CA_DB_WAIT_TIMEOUT:-120}"
    log "Waiting up to ${TIMEOUT}s for database at ${DB_HOST}:${DB_PORT}"
    elapsed=0
    until php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $pw = getenv("CA_DB_PASSWORD_FILE") ? trim(@file_get_contents(getenv("CA_DB_PASSWORD_FILE"))) : getenv("CA_DB_PASSWORD");
        $c = @new mysqli(getenv("CA_DB_HOST") ?: "db", getenv("CA_DB_USER") ?: "collectiveaccess", $pw ?: "", getenv("CA_DB_DATABASE") ?: "collectiveaccess", (int)(getenv("CA_DB_PORT") ?: 3306));
        exit($c->connect_errno ? 1 : 0);
    ' 2>/dev/null; do
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$TIMEOUT" ]; then
            log "ERROR: database not reachable after ${TIMEOUT}s"
            exit 1
        fi
        sleep 2
    done
    log "Database is reachable"
fi

# --- 4. Run ------------------------------------------------------------------
exec "$@"
