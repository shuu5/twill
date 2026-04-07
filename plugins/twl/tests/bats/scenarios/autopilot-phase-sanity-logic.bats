#!/usr/bin/env bats
# autopilot-phase-sanity-logic.bats — behavior tests for Issue #139
#
# autopilot-phase-sanity.md の処理ロジックを bash で再現し、4 シナリオを検証する。
# 実 gh コマンドを呼ばず、PATH 先頭にモック gh を挿入する。
#
# シナリオ:
#  1. 全 done Issue が CLOSED         → results 不変
#  2. 1 Issue OPEN → close 成功         → auto_close_fallback に追加
#  3. 1 Issue OPEN → close 失敗         → done から failed に移動
#  4. state 取得失敗（空文字）          → sanity_warnings に追加 + done 維持

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TEST_TMP="$(mktemp -d)"
  PHASE_RESULTS_JSON="$TEST_TMP/phase-results.json"
  SESSION_STATE_FILE="$TEST_TMP/session.json"
  GH_MOCK_DIR="$TEST_TMP/bin"
  GH_STATE_DIR="$TEST_TMP/gh-state"
  mkdir -p "$GH_MOCK_DIR" "$GH_STATE_DIR"

  # mock gh
  cat > "$GH_MOCK_DIR/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
# usage:
#  gh issue view <N> --json state -q .state
#  gh issue close <N> [--comment ...]
set -uo pipefail
case "${1:-}" in
  issue)
    sub="${2:-}"
    issue="${3:-}"
    state_file="$GH_STATE_DIR/${issue}.state"
    case "$sub" in
      view)
        if [ -f "$state_file" ]; then
          cat "$state_file"
        else
          echo ""  # state-fetch-failed simulation
        fi
        ;;
      close)
        # close-allowed marker
        allow="$GH_STATE_DIR/${issue}.close-allowed"
        if [ -f "$allow" ]; then
          echo "CLOSED" > "$state_file"
          exit 0
        else
          exit 1
        fi
        ;;
    esac
    ;;
esac
MOCK_EOF
  chmod +x "$GH_MOCK_DIR/gh"

  export GH_STATE_DIR
  export PATH="$GH_MOCK_DIR:$PATH"
  export P=1
  export PHASE_RESULTS_JSON
  export SESSION_STATE_FILE

  echo '{}' > "$SESSION_STATE_FILE"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# Helper: run sanity logic (extracted from commands/autopilot-phase-sanity.md)
# ---------------------------------------------------------------------------
run_sanity() {
  DONE_LIST=$(jq -r '.done[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)
  FAILED_LIST=$(jq -r '.failed[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)
  SKIPPED_LIST=$(jq -r '.skipped[]' "$PHASE_RESULTS_JSON" 2>/dev/null || true)

  declare -a NEW_DONE=()
  declare -a NEW_FAILED=()
  declare -a AUTO_CLOSE_FALLBACK=()
  declare -a SANITY_WARNINGS=()

  while IFS= read -r f; do [ -n "$f" ] && NEW_FAILED+=("$f"); done <<< "$FAILED_LIST"

  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    state=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "")
    case "$state" in
      CLOSED)
        NEW_DONE+=("$issue")
        ;;
      OPEN)
        gh issue close "$issue" --comment "auto-close-fallback" >/dev/null 2>&1 || true
        recheck=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "")
        if [ "$recheck" = "CLOSED" ]; then
          NEW_DONE+=("$issue")
          AUTO_CLOSE_FALLBACK+=("$issue")
        else
          NEW_FAILED+=("$issue")
        fi
        ;;
      "")
        SANITY_WARNINGS+=("issue=${issue} reason=state-fetch-failed")
        NEW_DONE+=("$issue")
        ;;
      *)
        SANITY_WARNINGS+=("issue=${issue} reason=unknown-state:${state}")
        NEW_DONE+=("$issue")
        ;;
    esac
  done <<< "$DONE_LIST"

  to_json_int_array() {
    if [ "$#" -eq 0 ]; then
      echo "[]"
    else
      printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length>0) | tonumber)'
    fi
  }
  to_json_str_array() {
    if [ "$#" -eq 0 ]; then
      echo "[]"
    else
      printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length>0))'
    fi
  }

  done_arr=$(to_json_int_array "${NEW_DONE[@]+"${NEW_DONE[@]}"}")
  failed_arr=$(to_json_int_array "${NEW_FAILED[@]+"${NEW_FAILED[@]}"}")
  skipped_arr=$(printf '%s\n' "$SKIPPED_LIST" | jq -R . | jq -s 'map(select(length>0) | tonumber)')
  fallback_arr=$(to_json_int_array "${AUTO_CLOSE_FALLBACK[@]+"${AUTO_CLOSE_FALLBACK[@]}"}")
  warnings_arr=$(to_json_str_array "${SANITY_WARNINGS[@]+"${SANITY_WARNINGS[@]}"}")

  jq -n \
    --argjson phase "$P" \
    --argjson done "$done_arr" \
    --argjson failed "$failed_arr" \
    --argjson skipped "$skipped_arr" \
    --argjson fallback "$fallback_arr" \
    --argjson warnings "$warnings_arr" \
    '{phase:$phase, done:$done, failed:$failed, skipped:$skipped, auto_close_fallback:$fallback, sanity_warnings:$warnings}' \
    > "${PHASE_RESULTS_JSON}.tmp" && mv "${PHASE_RESULTS_JSON}.tmp" "$PHASE_RESULTS_JSON"
}

# ---------------------------------------------------------------------------
# Scenario 1: 全 Issue CLOSED → results 不変
# ---------------------------------------------------------------------------
@test "scenario 1: all done issues CLOSED → results unchanged" {
  echo "CLOSED" > "$GH_STATE_DIR/100.state"
  echo "CLOSED" > "$GH_STATE_DIR/101.state"
  echo '{"phase":1,"done":[100,101],"failed":[],"skipped":[]}' > "$PHASE_RESULTS_JSON"

  run_sanity

  [ "$(jq -c '.done | sort' "$PHASE_RESULTS_JSON")" = "[100,101]" ]
  [ "$(jq -c '.failed' "$PHASE_RESULTS_JSON")" = "[]" ]
  [ "$(jq -c '.auto_close_fallback' "$PHASE_RESULTS_JSON")" = "[]" ]
  [ "$(jq -c '.sanity_warnings' "$PHASE_RESULTS_JSON")" = "[]" ]
}

# ---------------------------------------------------------------------------
# Scenario 2: OPEN → close 成功 → auto_close_fallback
# ---------------------------------------------------------------------------
@test "scenario 2: OPEN issue auto-closed → moved to auto_close_fallback" {
  echo "CLOSED" > "$GH_STATE_DIR/200.state"
  echo "OPEN"   > "$GH_STATE_DIR/201.state"
  touch "$GH_STATE_DIR/201.close-allowed"
  echo '{"phase":1,"done":[200,201],"failed":[],"skipped":[]}' > "$PHASE_RESULTS_JSON"

  run_sanity

  [ "$(jq -c '.done | sort' "$PHASE_RESULTS_JSON")" = "[200,201]" ]
  [ "$(jq -c '.failed' "$PHASE_RESULTS_JSON")" = "[]" ]
  [ "$(jq -c '.auto_close_fallback' "$PHASE_RESULTS_JSON")" = "[201]" ]
}

# ---------------------------------------------------------------------------
# Scenario 3: OPEN → close 失敗 → done から failed へ移動
# ---------------------------------------------------------------------------
@test "scenario 3: OPEN issue close failed → moved from done to failed" {
  echo "CLOSED" > "$GH_STATE_DIR/300.state"
  echo "OPEN"   > "$GH_STATE_DIR/301.state"
  # 301.close-allowed を作らない → close 失敗
  echo '{"phase":1,"done":[300,301],"failed":[],"skipped":[]}' > "$PHASE_RESULTS_JSON"

  run_sanity

  [ "$(jq -c '.done | sort' "$PHASE_RESULTS_JSON")" = "[300]" ]
  [ "$(jq -c '.failed' "$PHASE_RESULTS_JSON")" = "[301]" ]
  [ "$(jq -c '.auto_close_fallback' "$PHASE_RESULTS_JSON")" = "[]" ]
}

# ---------------------------------------------------------------------------
# Scenario 4: state 取得失敗 → sanity_warnings + done 維持
# ---------------------------------------------------------------------------
@test "scenario 4: state fetch failed → sanity_warnings + done preserved" {
  echo "CLOSED" > "$GH_STATE_DIR/400.state"
  # 401.state を作らない → 空文字返却
  echo '{"phase":1,"done":[400,401],"failed":[],"skipped":[]}' > "$PHASE_RESULTS_JSON"

  run_sanity

  [ "$(jq -c '.done | sort' "$PHASE_RESULTS_JSON")" = "[400,401]" ]
  [ "$(jq -c '.failed' "$PHASE_RESULTS_JSON")" = "[]" ]
  warnings=$(jq -c '.sanity_warnings' "$PHASE_RESULTS_JSON")
  [[ "$warnings" == *"401"* ]]
  [[ "$warnings" == *"state-fetch-failed"* ]]
}
