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
  [[ ! -f "$MANIFEST_FILE" ]] && continue

  # Extract context from filename: /tmp/.specialist-manifest-{context}.txt
  BASENAME=$(basename "$MANIFEST_FILE")
  CONTEXT="${BASENAME#.specialist-manifest-}"
  CONTEXT="${CONTEXT%.txt}"

  SPAWNED_FILE="/tmp/.specialist-spawned-${CONTEXT}.txt"

  # Refuse to write to symlinks (prevent symlink attack on /tmp files)
  [[ -L "$SPAWNED_FILE" ]] && continue

  # Read manifest (strip blank lines, comments, and twl:twl: prefix)
  mapfile -t MANIFEST_LIST < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||')
  [[ ${#MANIFEST_LIST[@]} -eq 0 ]] && continue

  # If current specialist is in this manifest, record it
  for entry in "${MANIFEST_LIST[@]}"; do
    if [[ "$SPECIALIST_NAME" == "$entry" ]]; then
      echo "$SPECIALIST_NAME" >> "$SPAWNED_FILE"
      sort -u "$SPAWNED_FILE" -o "$SPAWNED_FILE"
      break
    fi
  done

  # Check completeness
  SPAWNED_COUNT=0
  [[ -f "$SPAWNED_FILE" ]] && SPAWNED_COUNT=$(wc -l < "$SPAWNED_FILE")

  if [[ "$SPAWNED_COUNT" -ge "${#MANIFEST_LIST[@]}" ]]; then
    # All specialists spawned for this context, noop
    continue
  fi

  # Collect missing specialists
  if [[ -f "$SPAWNED_FILE" ]]; then
    mapfile -t MISSING < <(comm -23 \
      <(printf '%s\n' "${MANIFEST_LIST[@]}" | sort) \
      <(sort "$SPAWNED_FILE"))
  else
    MISSING=("${MANIFEST_LIST[@]}")
  fi

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    for m in "${MISSING[@]}"; do
      echo "⚠ specialist spawn 未完了: ${m} が未 spawn です [context: ${CONTEXT}]"
    done
  fi
done

exit 0
