#!/usr/bin/env bash
# PostToolUse hook: specialist spawn completeness checker (generic)
#
# Fires after Agent or Task tool use.
# Tracks spawned specialists against a manifest file, warns on missing ones.
#
# Manifest file: /tmp/.specialist-manifest-{context}.txt
#   Each line: one specialist name (without twl:twl: prefix)
# Spawn tracking: /tmp/.specialist-spawned-{context}.txt
#   Each line: one spawned specialist name (recorded by this hook)
#
# Lifecycle:
#   - Manifest created/deleted by context side (issue-spec-review, phase-review, etc.)
#   - This hook only reads manifest and updates spawn tracking

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL_NAME" in
  Agent|Task) ;;
  *) exit 0 ;;
esac

SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[[ -z "$SUBAGENT_TYPE" ]] && exit 0

# Strip twl:twl: prefix for comparison
SPECIALIST_NAME="${SUBAGENT_TYPE#twl:twl:}"

# Validate: allow only safe characters (prevent content injection via newlines/control chars)
[[ "$SPECIALIST_NAME" =~ ^[a-zA-Z0-9:_-]+$ ]] || exit 0

# Find all active manifest files
shopt -s nullglob
MANIFEST_FILES=(/tmp/.specialist-manifest-*.txt)
shopt -u nullglob

[[ ${#MANIFEST_FILES[@]} -eq 0 ]] && exit 0

for MANIFEST_FILE in "${MANIFEST_FILES[@]}"; do
  # Refuse symlinks for manifest (prevent manifest content injection via symlink)
  [[ -L "$MANIFEST_FILE" ]] && continue
  [[ ! -f "$MANIFEST_FILE" ]] && continue

  # Extract context from filename: /tmp/.specialist-manifest-{context}.txt
  BASENAME=$(basename "$MANIFEST_FILE")
  CONTEXT="${BASENAME#.specialist-manifest-}"
  CONTEXT="${CONTEXT%.txt}"

  # Validate context: allow only safe characters (prevent path traversal and log injection)
  [[ "$CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]] || continue

  SPAWNED_FILE="/tmp/.specialist-spawned-${CONTEXT}.txt"

  # Read manifest (strip blank lines, comments, and twl:twl: prefix)
  mapfile -t MANIFEST_LIST < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||')
  [[ ${#MANIFEST_LIST[@]} -eq 0 ]] && continue

  # If current specialist is in this manifest, record it atomically with flock
  # (prevents race condition and TOCTOU between check and write)
  for entry in "${MANIFEST_LIST[@]}"; do
    if [[ "$SPECIALIST_NAME" == "$entry" ]]; then
      {
        flock 9
        echo "$SPECIALIST_NAME" >> "$SPAWNED_FILE"
        sort -u "$SPAWNED_FILE" -o "$SPAWNED_FILE"
      } 9>> "$SPAWNED_FILE"
      break
    fi
  done

  # Check completeness using set difference (more accurate than count comparison)
  mapfile -t MISSING < <(comm -23 \
    <(printf '%s\n' "${MANIFEST_LIST[@]}" | sort) \
    <( [[ -f "$SPAWNED_FILE" ]] && sort "$SPAWNED_FILE" || true ))

  if [[ ${#MISSING[@]} -eq 0 ]]; then
    # All specialists spawned for this context, noop
    continue
  fi

  for m in "${MISSING[@]}"; do
    printf '⚠ specialist spawn 未完了: %s が未 spawn です [context: %s]\n' "$m" "$CONTEXT"
  done
done

exit 0
