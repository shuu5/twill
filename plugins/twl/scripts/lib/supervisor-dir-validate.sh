#!/usr/bin/env bash
# supervisor-dir-validate.sh — SUPERVISOR_DIR パス検証共有 lib
#
# Usage (source this file, then call the function):
#   source "$(dirname "$0")/lib/supervisor-dir-validate.sh"
#   validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1
#
# Validates that a SUPERVISOR_DIR value is safe to use with mkdir -p / file path ops.
# Rejects: path traversal (..), absolute paths (/...), and shell-injection chars.
# Allowed: alphanumeric, dot, hyphen, underscore, slash (relative paths only).

# validate_supervisor_dir <dir>
#   Returns: 0 (valid), 1 (invalid, prints ERROR to stderr)
validate_supervisor_dir() {
  local _dir="${1:-}"
  if [[ "$_dir" == *..* ]]; then
    echo "ERROR: SUPERVISOR_DIR must not contain '..'" >&2
    return 1
  fi
  if [[ "$_dir" =~ ^/ ]]; then
    echo "ERROR: SUPERVISOR_DIR must not be an absolute path (got: ${_dir})" >&2
    return 1
  fi
  if [[ ! "$_dir" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    echo "ERROR: SUPERVISOR_DIR must only contain allowed characters (alphanumeric, dot, hyphen, underscore, slash)" >&2
    return 1
  fi
}
