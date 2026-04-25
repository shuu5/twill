#!/usr/bin/env bats
# permission-ui-response-deny-escalate.bats - AC4: sudo → STOP + Layer 2 Escalate
#
# Issue #973: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# Coverage (RED phase — soft_deny_match.py 未実装のため全テスト fail):
#   1. fixture ファイルが存在する
#   2. sudo prompt → match-escalate を返す (RED: 未実装)
#   3. match-escalate 時に Layer 2 Escalate 昇格 (STOP) (RED: 未実装)
#
# AC: prompt = "sudo systemctl ..." → STOP + Layer 2 Escalate 昇格

load '../helpers/common'

FIXTURE=""
CLI_SRC=""

setup() {
  common_setup
  FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/permission-ui-deny-escalate.txt"
  CLI_SRC="$(cd "$REPO_ROOT/../../cli/twl/src" && pwd)"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Prereq: fixture が存在すること
# ---------------------------------------------------------------------------

@test "AC4-deny-escalate: fixture ファイルが存在する" {
  [ -f "$FIXTURE" ] || fail "fixture が存在しない: $FIXTURE"
}

# ---------------------------------------------------------------------------
# RED: sudo → match-escalate (AC2, AC3, AC7)
# ---------------------------------------------------------------------------

@test "AC4-deny-escalate: sudo prompt → soft_deny_match が match-escalate を返す (RED: 未実装)" {
  local result
  result=$(PYTHONPATH="$CLI_SRC" python3 -m twl.intervention.soft_deny_match < "$FIXTURE") \
    || fail "soft_deny_match 実行失敗 (exit=$?)"
  echo "$result" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d['result']=='match-escalate', f'expected match-escalate got {d}'" \
    || fail "expected match-escalate but got: $result"
}

# ---------------------------------------------------------------------------
# RED: match-escalate の rule が privilege-escalation (AC3)
# ---------------------------------------------------------------------------

@test "AC4-deny-escalate: match-escalate の rule が privilege-escalation (RED: 未実装)" {
  local result
  result=$(PYTHONPATH="$CLI_SRC" python3 -m twl.intervention.soft_deny_match < "$FIXTURE") \
    || fail "soft_deny_match 実行失敗"
  echo "$result" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d.get('rule')=='privilege-escalation', f'expected privilege-escalation got {d}'" \
    || fail "expected rule=privilege-escalation but got: $result"
}

# ---------------------------------------------------------------------------
# RED: STOP + Layer 2 Escalate 昇格フラグ (AC2, AC7)
# ---------------------------------------------------------------------------

@test "AC4-deny-escalate: match-escalate 時に Layer 2 Escalate 昇格フラグが立つ (RED: 未実装)" {
  local result
  result=$(PYTHONPATH="$CLI_SRC" python3 -m twl.intervention.soft_deny_match < "$FIXTURE") \
    || fail "soft_deny_match 実行失敗"
  echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['result'] == 'match-escalate', f'not match-escalate: {d}'
assert d.get('layer') in ('escalate', 2), f'unexpected layer: {d}'
" || fail "Layer 2 Escalate 昇格フラグ検証失敗: $result"
}
