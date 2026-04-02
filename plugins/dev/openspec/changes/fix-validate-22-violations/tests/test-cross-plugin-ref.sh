#!/usr/bin/env bash
# test-cross-plugin-ref.sh
# Scenario: cross-plugin 参照移行の検証
# change-id: fix-validate-22-violations

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPS_YAML="$REPO_ROOT/deps.yaml"
PASS=0
FAIL=0

# ---- helpers ----

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }

# calls エントリのキー一覧を取得するヘルパー
# 引数: section component
_calls_keys() {
  local section="$1" component="$2"
  python3 - "$DEPS_YAML" "$section" "$component" <<'PYEOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
section   = sys.argv[2]
component = sys.argv[3]
comp_data = data.get(section, {}).get(component, {})
calls     = comp_data.get('calls', [])
for i, call in enumerate(calls):
    print(f"{i}:{','.join(call.keys())}")
PYEOF
}

# calls 内に指定キーが存在するか確認
# 戻り値: 0=存在する, 1=存在しない
_calls_has_key() {
  local section="$1" component="$2" key="$3"
  python3 - "$DEPS_YAML" "$section" "$component" "$key" <<'PYEOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
section   = sys.argv[2]
component = sys.argv[3]
key       = sys.argv[4]
calls     = data.get(section, {}).get(component, {}).get('calls', [])
found = any(key in call for call in calls)
sys.exit(0 if found else 1)
PYEOF
}

# calls 内に指定値を持つエントリが存在するか
# 引数: section component key value
_calls_has_value() {
  local section="$1" component="$2" key="$3" value="$4"
  python3 - "$DEPS_YAML" "$section" "$component" "$key" "$value" <<'PYEOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
section   = sys.argv[2]
component = sys.argv[3]
key       = sys.argv[4]
value     = sys.argv[5]
calls     = data.get(section, {}).get(component, {}).get('calls', [])
found = any(call.get(key) == value for call in calls)
sys.exit(0 if found else 1)
PYEOF
}

# ---- Scenario: autopilot-poll の calls 修正 ----
# WHEN: autopilot-poll の calls に external: session-state.sh エントリが存在する
# THEN: 当該エントリを - script: session:session-state に置換し、
#       path/optional/note キーを除去する

test_autopilot_poll_no_external_keys() {
  local component="autopilot-poll"
  local section="commands"

  if _calls_has_key "$section" "$component" "external"; then
    fail "$component: calls に 'external' キーが残存している"
  else
    pass "$component: calls に 'external' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "path"; then
    fail "$component: calls に 'path' キーが残存している"
  else
    pass "$component: calls に 'path' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "optional"; then
    fail "$component: calls に 'optional' キーが残存している"
  else
    pass "$component: calls に 'optional' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "note"; then
    fail "$component: calls に 'note' キーが残存している"
  else
    pass "$component: calls に 'note' キーが存在しない"
  fi
}

test_autopilot_poll_has_cross_plugin_ref() {
  local component="autopilot-poll"
  local section="commands"

  if _calls_has_value "$section" "$component" "script" "session:session-state"; then
    pass "$component: calls に 'script: session:session-state' が存在する"
  else
    fail "$component: calls に 'script: session:session-state' が存在しない"
  fi
}

# ---- Scenario: autopilot-phase-execute の calls 修正 ----

test_autopilot_phase_execute_no_external_keys() {
  local component="autopilot-phase-execute"
  local section="commands"

  if _calls_has_key "$section" "$component" "external"; then
    fail "$component: calls に 'external' キーが残存している"
  else
    pass "$component: calls に 'external' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "path"; then
    fail "$component: calls に 'path' キーが残存している"
  else
    pass "$component: calls に 'path' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "optional"; then
    fail "$component: calls に 'optional' キーが残存している"
  else
    pass "$component: calls に 'optional' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "note"; then
    fail "$component: calls に 'note' キーが残存している"
  else
    pass "$component: calls に 'note' キーが存在しない"
  fi
}

test_autopilot_phase_execute_has_cross_plugin_ref() {
  local component="autopilot-phase-execute"
  local section="commands"

  if _calls_has_value "$section" "$component" "script" "session:session-state"; then
    pass "$component: calls に 'script: session:session-state' が存在する"
  else
    fail "$component: calls に 'script: session:session-state' が存在しない"
  fi
}

# ---- Scenario: crash-detect の calls 修正 ----

test_crash_detect_no_external_keys() {
  local component="crash-detect"
  local section="scripts"

  if _calls_has_key "$section" "$component" "external"; then
    fail "$component: calls に 'external' キーが残存している"
  else
    pass "$component: calls に 'external' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "path"; then
    fail "$component: calls に 'path' キーが残存している"
  else
    pass "$component: calls に 'path' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "optional"; then
    fail "$component: calls に 'optional' キーが残存している"
  else
    pass "$component: calls に 'optional' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "note"; then
    fail "$component: calls に 'note' キーが残存している"
  else
    pass "$component: calls に 'note' キーが存在しない"
  fi
}

test_crash_detect_has_cross_plugin_ref() {
  local component="crash-detect"
  local section="scripts"

  if _calls_has_value "$section" "$component" "script" "session:session-state"; then
    pass "$component: calls に 'script: session:session-state' が存在する"
  else
    fail "$component: calls に 'script: session:session-state' が存在しない"
  fi
}

# ---- Scenario: health-check の calls 修正 ----

test_health_check_no_external_keys() {
  local component="health-check"
  local section="scripts"

  if _calls_has_key "$section" "$component" "external"; then
    fail "$component: calls に 'external' キーが残存している"
  else
    pass "$component: calls に 'external' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "path"; then
    fail "$component: calls に 'path' キーが残存している"
  else
    pass "$component: calls に 'path' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "optional"; then
    fail "$component: calls に 'optional' キーが残存している"
  else
    pass "$component: calls に 'optional' キーが存在しない"
  fi

  if _calls_has_key "$section" "$component" "note"; then
    fail "$component: calls に 'note' キーが残存している"
  else
    pass "$component: calls に 'note' キーが存在しない"
  fi
}

test_health_check_has_cross_plugin_ref() {
  local component="health-check"
  local section="scripts"

  if _calls_has_value "$section" "$component" "script" "session:session-state"; then
    pass "$component: calls に 'script: session:session-state' が存在する"
  else
    fail "$component: calls に 'script: session:session-state' が存在しない"
  fi
}

# ---- Scenario: validate 全件 PASS ----
# WHEN: deps.yaml 修正後に loom validate を実行する
# THEN: Violations: 0 が出力され、exit code 0 で終了する

test_validate_all() {
  local output exit_code
  output=$(cd "$REPO_ROOT" && loom validate 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}

  if [[ $exit_code -eq 0 ]]; then
    pass "loom validate: exit code 0"
  else
    fail "loom validate: exit code $exit_code (expected 0)"
  fi

  if echo "$output" | grep -qE "Violations: 0"; then
    pass "loom validate: 'Violations: 0' を含む出力"
  else
    fail "loom validate: 'Violations: 0' が出力に含まれない。実際の出力:"$'\n'"$output"
  fi

  if echo "$output" | grep -q "v3-calls-key"; then
    fail "loom validate: v3-calls-key violation が残存している"$'\n'"$output"
  else
    pass "loom validate: v3-calls-key violation が存在しない"
  fi
}

# ---- Scenario: check 全件 PASS ----
# WHEN: deps.yaml 修正後に loom check を実行する
# THEN: Missing: 0 が出力される

test_check_missing_zero() {
  local output
  output=$(cd "$REPO_ROOT" && loom check 2>&1)

  if echo "$output" | grep -qE "Missing: 0"; then
    pass "loom check: 'Missing: 0' を含む出力"
  else
    fail "loom check: 'Missing: 0' が出力に含まれない。実際の出力:"$'\n'"$output"
  fi
}

# ---- edge-case: 対象コンポーネントの既存 script 参照が壊れていないか ----

test_autopilot_poll_existing_scripts_intact() {
  local section="commands" component="autopilot-poll"
  local intact=1

  for script in "state-read" "state-write" "crash-detect"; do
    if ! _calls_has_value "$section" "$component" "script" "$script"; then
      fail "$component: 既存 script '$script' が calls から消えている"
      intact=0
    fi
  done

  if [[ $intact -eq 1 ]]; then
    pass "$component: 既存の script 参照 (state-read, state-write, crash-detect) が保持されている"
  fi
}

test_autopilot_phase_execute_existing_scripts_intact() {
  local section="commands" component="autopilot-phase-execute"
  local intact=1

  for script in "state-read" "state-write" "autopilot-should-skip" "health-check"; do
    if ! _calls_has_value "$section" "$component" "script" "$script"; then
      fail "$component: 既存 script '$script' が calls から消えている"
      intact=0
    fi
  done

  if [[ $intact -eq 1 ]]; then
    pass "$component: 既存の script 参照が保持されている"
  fi
}

test_crash_detect_existing_scripts_intact() {
  local section="scripts" component="crash-detect"
  local intact=1

  for script in "state-read" "state-write"; do
    if ! _calls_has_value "$section" "$component" "script" "$script"; then
      fail "$component: 既存 script '$script' が calls から消えている"
      intact=0
    fi
  done

  if [[ $intact -eq 1 ]]; then
    pass "$component: 既存の script 参照 (state-read, state-write) が保持されている"
  fi
}

test_health_check_existing_scripts_intact() {
  local section="scripts" component="health-check"

  if _calls_has_value "$section" "$component" "script" "state-read"; then
    pass "$component: 既存の script 参照 (state-read) が保持されている"
  else
    fail "$component: 既存 script 'state-read' が calls から消えている"
  fi
}

# ---- main ----

main() {
  echo "=== cross-plugin-ref-migration テスト ==="
  echo "DEPS_YAML: $DEPS_YAML"
  echo ""

  # deps.yaml 構造テスト
  echo "--- deps.yaml 構造検証 ---"
  test_autopilot_poll_no_external_keys
  test_autopilot_poll_has_cross_plugin_ref
  test_autopilot_phase_execute_no_external_keys
  test_autopilot_phase_execute_has_cross_plugin_ref
  test_crash_detect_no_external_keys
  test_crash_detect_has_cross_plugin_ref
  test_health_check_no_external_keys
  test_health_check_has_cross_plugin_ref

  # 既存参照が保たれているか（edge-case）
  echo ""
  echo "--- edge-case: 既存 script 参照の保全 ---"
  test_autopilot_poll_existing_scripts_intact
  test_autopilot_phase_execute_existing_scripts_intact
  test_crash_detect_existing_scripts_intact
  test_health_check_existing_scripts_intact

  # loom CLI テスト
  echo ""
  echo "--- loom CLI 検証 ---"
  test_validate_all
  test_check_missing_zero

  echo ""
  echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="

  if [[ $FAIL -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
