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

  # Refuse symlinks for spawned tracking file (prevent symlink attack on write target)
  [[ -L "$SPAWNED_FILE" ]] && continue

  # Read manifest (strip blank lines, comments, twl:twl: prefix, and unsafe entries)
  mapfile -t MANIFEST_LIST < <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||' | grep -E '^[a-zA-Z0-9:_-]+$')
  [[ ${#MANIFEST_LIST[@]} -eq 0 ]] && continue

  # If current specialist is in this manifest, record it atomically with flock
  # (prevents race condition and TOCTOU between check and write)
  for entry in "${MANIFEST_LIST[@]}"; do
    if [[ "$SPECIALIST_NAME" == "$entry" ]]; then
      {
        flock 9
        echo "$SPECIALIST_NAME" >> "$SPAWNED_FILE"
        LC_ALL=C sort -u "$SPAWNED_FILE" -o "$SPAWNED_FILE"
      } 9>> "$SPAWNED_FILE"
      break
    fi
  done

  # Check completeness using set difference (more accurate than count comparison)
  mapfile -t MISSING < <(LC_ALL=C comm -23 \
    <(printf '%s\n' "${MANIFEST_LIST[@]}" | LC_ALL=C sort) \
    <( [[ -f "$SPAWNED_FILE" ]] && LC_ALL=C sort "$SPAWNED_FILE" || true ))

  if [[ ${#MISSING[@]} -eq 0 ]]; then
    # All specialists spawned for this context
    # spec-review- context の場合: セッション state の completed をインクリメント
    if [[ "$CONTEXT" == spec-review-* ]]; then
      HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
      SESSION_STATE="/tmp/.spec-review-session-${HASH}.json"
      SESSION_LOCK="/tmp/.spec-review-session-${HASH}.lock"
      # SESSION_LOCK の symlink チェック（flock 前に実施 — symlink following 対策）
      if [[ -L "$SESSION_LOCK" ]]; then
        printf '⚠ spec-review session: SESSION_LOCK が symlink — インクリメントをスキップ [context: %s]\n' "$CONTEXT"
      elif [[ -f "$SESSION_STATE" && ! -L "$SESSION_STATE" ]]; then
        # flock 失敗時はサイレントスキップではなく警告を出す（カウント消失防止）
        {
          if ! flock -w 5 8; then
            printf '⚠ spec-review session: flock 取得失敗（タイムアウト）— completed インクリメントをスキップ [context: %s]\n' "$CONTEXT"
          else
            # SESSION_STATE の symlink 再チェック（flock 取得後）
            if [[ -L "$SESSION_STATE" ]]; then
              printf '⚠ spec-review session: STATE_FILE が symlink — インクリメントをスキップ [context: %s]\n' "$CONTEXT"
            elif [[ ! -L "${SESSION_STATE}.tmp" ]]; then
              CURRENT=$(jq -r '.completed // 0' "$SESSION_STATE" 2>/dev/null || echo "0")
              if [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
                if jq ".completed = (.completed + 1)" "$SESSION_STATE" > "${SESSION_STATE}.tmp"; then
                  mv "${SESSION_STATE}.tmp" "$SESSION_STATE"
                else
                  rm -f "${SESSION_STATE}.tmp"
                  printf '⚠ spec-review session: jq 失敗 — completed インクリメントをスキップ [context: %s]\n' "$CONTEXT"
                fi
              fi
            else
              printf '⚠ spec-review session: .tmp ファイルが symlink — インクリメントをスキップ [context: %s]\n' "$CONTEXT"
            fi
          fi
        } 8>"$SESSION_LOCK"
        # SESSION_LOCK クリーンアップ（flock 解放後）
        rm -f "$SESSION_LOCK"
      fi
    fi
    # Clean up manifest and spawned tracking files
    rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"
    continue
  fi

  TOTAL=${#MANIFEST_LIST[@]}
  SPAWNED=$((TOTAL - ${#MISSING[@]}))
  printf '⚠ specialist spawn 未完了: %d/%d 完了 [context: %s]\n' "$SPAWNED" "$TOTAL" "$CONTEXT"
  printf '  未 spawn specialist:\n'
  for m in "${MISSING[@]}"; do
    printf '    - %s → Task(subagent_type="twl:twl:%s") で spawn すること\n' "$m" "$m"
  done
  printf '  結果集約に進む前に全 specialist を spawn してください。\n'
done

exit 0
