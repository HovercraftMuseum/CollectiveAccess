#!/bin/sh
# Delete Providence log files older than CA_LOG_KEEP_DAYS (from .env,
# default 30). Providence starts new log files every day and never removes
# old ones.
#
# Run it daily on the host, e.g. from cron, from the folder holding
# compose.yaml and .env:
#
#   scripts/prune-logs.sh
set -eu

STACK_DIR="${STACK_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$STACK_DIR"

# Read a single value from .env without executing it.
env_get() {
    sed -n "s/^$1=//p" .env | tail -n 1 | sed 's/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}

KEEP_DAYS="$(env_get CA_LOG_KEEP_DAYS)"
KEEP_DAYS="${KEEP_DAYS:-30}"
case "$KEEP_DAYS" in
    *[!0-9]*) echo "[prune-logs] CA_LOG_KEEP_DAYS must be a whole number of days" >&2; exit 1 ;;
esac

echo "[prune-logs] Removing Providence log files older than $KEEP_DAYS days"
docker compose exec -T web find /var/lib/collectiveaccess/log -maxdepth 1 -type f \
    -name 'log_*.txt' -mtime +"$KEEP_DAYS" -print -delete
