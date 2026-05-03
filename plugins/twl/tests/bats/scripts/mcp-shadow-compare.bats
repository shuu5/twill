#!/usr/bin/env bats
# mcp-shadow-compare.bats
#
# AC-5: 比較スクリプト mcp-shadow-compare.sh の整合性を 5 サンプルで検証
# (Issue #1225)
#
# 5 サンプルシナリオ (Issue AC-5 仕様):
#   1. valid deps.yaml Write    : bash=allow, mcp=allow  → 判定一致 (exit 0)
#   2. invalid YAML syntax      : bash=block, mcp=block  → 判定一致 (exit 0)
#   3. path traversal           : bash=block, mcp=block  → 判定一致 (exit 0)
#   4. large YAML (10MB 超)     : bash=error, mcp=error  → 判定一致 (exit 0)
#   5. 非 deps.yaml file Write  : bash=skip,  mcp=skip   → 判定一致 (exit 0)
#
# 追加: mismatch 検出テスト (比較スクリプトの正確性確認)
#   6. bash=allow, mcp=block    → mismatch → exit 1, stderr に MISMATCH
#
# 全テストは mcp-shadow-compare.sh 未実装のため RED (fail) する。
#

load '../helpers/common'

COMPARE_SH=""

setup() {
  common_setup

  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
  COMPARE_SH="${git_root}/plugins/twl/scripts/mcp-shadow-compare.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: JSONL ログファイルを作成して mcp-shadow-compare.sh を実行する
# 引数:
#   $1 = bash 判定 ("allow", "block", "error", "skip")
#   $2 = mcp 判定  ("allow", "block", "error", "skip")
#   $3 = イベント ID (event_id)
# ---------------------------------------------------------------------------
_run_compare_with_log() {
  local bash_verdict="$1"
  local mcp_verdict="$2"
  local event_id="${3:-evt-001}"

  local log_file="$SANDBOX/deps-yaml-shadow.log"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # bash hook エントリ
  printf '%s\n' "$(jq -nc \
    --arg id "$event_id" \
    --arg ts "$ts" \
    --arg v "$bash_verdict" \
    '{event_id:$id, ts:$ts, source:"bash", verdict:$v, tool_name:"Write", file_path:"deps.yaml"}')" \
    >> "$log_file"

  # mcp_tool エントリ
  printf '%s\n' "$(jq -nc \
    --arg id "$event_id" \
    --arg ts "$ts" \
    --arg v "$mcp_verdict" \
    '{event_id:$id, ts:$ts, source:"mcp_tool", verdict:$v, tool_name:"Write", file_path:"deps.yaml"}')" \
    >> "$log_file"

  run bash "$COMPARE_SH" --log-file "$log_file"
}

# ---------------------------------------------------------------------------
# 前提: mcp-shadow-compare.sh が存在しなければ全テスト fail（RED 確認）
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Sample 1: valid deps.yaml Write (bash=allow, mcp=allow) → 判定一致 (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample1: valid deps.yaml Write — bash=allow mcp=allow → 判定一致 (exit 0)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "allow" "allow" "evt-valid-yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 2: invalid YAML syntax (bash=block, mcp=block) → 判定一致 (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample2: invalid YAML syntax — bash=block mcp=block → 判定一致 (exit 0)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "block" "block" "evt-invalid-yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 3: path traversal (bash=block, mcp=block) → 判定一致 (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample3: path traversal — bash=block mcp=block → 判定一致 (exit 0)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "block" "block" "evt-path-traversal"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 4: 巨大 YAML 10MB 超 Write (bash=error, mcp=error) → 判定一致 (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample4: 巨大 YAML (10MB 超) Write — bash=error mcp=error → 判定一致 (exit 0)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "error" "error" "evt-large-yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 5: 非 deps.yaml file Write (bash=skip, mcp=skip) → 判定一致 (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample5: 非 deps.yaml file Write — bash=skip mcp=skip → 判定一致 (exit 0)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "skip" "skip" "evt-non-deps-yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Extra: mismatch 検出 (bash=allow, mcp=block) → exit 1, stderr に MISMATCH
# ---------------------------------------------------------------------------

@test "AC5 extra: mismatch — bash=allow mcp=block → exit 1 (MISMATCH 検出)" {
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "allow" "block" "evt-mismatch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH"* ]] || [[ "$stderr" == *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Issue #1285: set -euo pipefail への統一（-e 欠如修正）
# ---------------------------------------------------------------------------

@test "ac1 (Issue #1285): mcp-shadow-compare.sh が set -euo pipefail を使用している" {
  # AC: set -uo pipefail → set -euo pipefail に変更（-e 欠如修正）
  # RED: 実装前は fail する（現在 set -uo pipefail で -e が欠如）
  grep -q "^set -euo pipefail" "$COMPARE_SH"
}
