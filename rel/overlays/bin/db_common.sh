#!/bin/sh
# Shared helpers for the offline database maintenance scripts. This file is
# sourced, never executed.
#
# The database path is resolved exactly the way `config/runtime.exs` resolves
# it, so the scripts always operate on the file the app would use, however the
# container was configured.

CONFIG_PATH="${CONFIG_PATH:-/config}"
DATABASE_PATH="${DATABASE_PATH:-${CONFIG_PATH}/db/pinchflat.db}"

db_die() {
  echo "Error: $*" >&2
  exit 1
}

db_require_sqlite3() {
  command -v sqlite3 >/dev/null 2>&1 || db_die "the sqlite3 CLI is not available in this image"
}

db_require_database() {
  [ -f "${DATABASE_PATH}" ] || db_die "no database found at ${DATABASE_PATH} (set DATABASE_PATH or CONFIG_PATH)"
}

# Single quotes can't be escaped inside the SQL string literals these scripts
# build, so a path containing one is rejected rather than silently mangled.
db_reject_quoted_path() {
  case "$1" in
    *"'"*) db_die "path contains a single quote, which can't be used in a SQL string: $1" ;;
  esac
}

# These scripts are meant to be run in maintenance mode, where nothing has the
# database open. They also work against a running app (SQLite handles
# concurrent readers), but the operator should know which situation they're in
# — a backup taken mid-download is a snapshot of a moving target.
# Matched against the release's own ERTS path (the release is unpacked at
# /app) so an unrelated BEAM elsewhere on the host can't trip the warning
db_running_app_pid() {
  pgrep -f '/app/erts-.*/bin/beam.smp' 2>/dev/null | head -n 1
}

db_warn_if_app_running() {
  if [ -n "$(db_running_app_pid)" ]; then
    echo "Warning: Tubeless is currently running against ${DATABASE_PATH}." >&2
    echo "         For a clean result, restart the container with MAINTENANCE_MODE=true first." >&2
    echo "" >&2
  fi
}

db_file_size() {
  if [ -f "$1" ]; then
    du -h "$1" 2>/dev/null | cut -f1
  else
    echo "0"
  fi
}
