#!/usr/bin/env bats
# permission-ui-response-safe.bats - AC4: safe prompt → inject "1" + InterventionRecord
#
# Issue #973: observer Auto レイヤーの permission UI menu 自動代理応答対応
#
# Coverage (RED phase — soft_deny_match.py 未実装のため全テスト fail):
#   1. fixture ファイルが存在する
#   2. soft_deny_match モジュールが存在する (RED: 未実装)
#   3. safe prompt (Read file) → no-match を返す (RED: 未実装)
#   4. no-match 時の InterventionRecord 記録 (RED: 未実装)
#
# AC: prompt = "Read file foo.md" → inject "1" 成功 + InterventionRecord 記録

load '../helpers/common'

# API contract: soft_deny_match は2つのインターフェースを持つ
#   1. CLI モード: stdin 経由でペイン内容を受け取り JSON を stdout に出力
#      例: python3 -m twl.intervention.soft_deny_match < fixture.txt
#   2. Python API: match_prompt(pane: str) -> MatchResult を直接呼ぶ
#      例: from twl.intervention.soft_deny_match import match_prompt; match_prompt(text)
# bats テストは CLI モード (stdin) を使用し、pytest は Python API を使用する。
# 両インターフェースは同一ロジックを呼び出すこと (MUST)。

FIXTURE=""
CLI_SRC=""

setup() {
  common_setup
  FIXTURE="${BATS_TEST_DIRNAME}/../fixtures/permission-ui-safe.txt"
  CLI_SRC="$(cd "$REPO_ROOT/../../cli/twl/src" && pwd)"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Prereq: fixture が存在すること
# ---------------------------------------------------------------------------

@test "AC4-safe: fixture ファイルが存在する" {
  [ -f "$FIXTURE" ] || fail "fixture が存在しない: $FIXTURE"
}

# ---------------------------------------------------------------------------
# RED: soft_deny_match モジュールの存在確認 (AC2)
# ---------------------------------------------------------------------------

@test "AC4-safe: soft_deny_match.py が存在する (RED: 未実装)" {
  local module_path="$CLI_SRC/twl/intervention/soft_deny_match.py"
  [ -f "$module_path" ] || fail "soft_deny_match.py が存在しない: $module_path"
}

# ---------------------------------------------------------------------------
# RED: safe prompt → no-match (AC2, AC7)
# ---------------------------------------------------------------------------

@test "AC4-safe: safe prompt → soft_deny_match が no-match を返す (RED: 未実装)" {
  local result
  result=$(PYTHONPATH="$CLI_SRC" python3 -m twl.intervention.soft_deny_match < "$FIXTURE") \
    || fail "soft_deny_match 実行失敗 (exit=$?)"
  echo "$result" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d['result']=='no-match', f'expected no-match got {d}'" \
    || fail "expected no-match but got: $result"
}

# ---------------------------------------------------------------------------
# RED: InterventionRecord が .observation/ に記録される (AC2)
# ---------------------------------------------------------------------------

@test "AC4-safe: no-match 時に InterventionRecord が記録される (RED: 未実装)" {
  local obs_dir="$SANDBOX/.observation/test-session-safe"
  mkdir -p "$obs_dir"
  PYTHONPATH="$CLI_SRC" python3 -m twl.intervention.soft_deny_match \
    --record-intervention \
    --session-id test-session-safe \
    --observation-dir "$obs_dir" \
    < "$FIXTURE" \
    || fail "soft_deny_match --record-intervention 実行失敗"
  local record_count
  record_count=$(find "$obs_dir" -name "intervention-*.json" 2>/dev/null | wc -l)
  [ "$record_count" -ge 1 ] || fail "InterventionRecord が記録されなかった (found: $record_count)"
}
