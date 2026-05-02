#!/usr/bin/env bats
# mcp-shadow-compare.bats
#
# AC-5: 比較スクリプト mcp-shadow-compare.sh の整合性を 5 サンプルで検証
# (Issue #1225)
#
# WHEN mcp-shadow-compare.sh が実装されている
# THEN 同一 event の bash 判定と mcp_tool 判定を突合し:
#   - both_allow  : bash=allow, mcp=allow  → exit 0, mismatch なし
#   - both_block  : bash=block, mcp=block  → exit 0, mismatch なし
#   - bash_allow_mcp_block: mismatch       → exit 1, stderr に mismatch 出力
#   - bash_block_mcp_allow: mismatch       → exit 1, stderr に mismatch 出力
#   - empty_log   : ログ行が 0 件           → exit 0, mismatch なし (no events)
#
# 全テストは mcp-shadow-compare.sh 未実装のため RED (fail) する。
#
# Source guard チェック:
#   mcp-shadow-compare.sh はスタンドアロンスクリプト（source 不要）のため
#   source guard チェックは不要。bash <script> で直接実行する。
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
# 前提: mcp-shadow-compare.sh が存在しなければ全テスト fail（RED 確認）
# ---------------------------------------------------------------------------

# Helper: JSONL ログファイルを作成して mcp-shadow-compare.sh を実行する
# 引数:
#   $1 = bash 判定 ("allow" or "block")
#   $2 = mcp 判定  ("allow" or "block")
#   $3 = イベント ID (event_id)
# 標準入力としてログ行を渡す方式ではなく、--log-file オプション経由。
_run_compare_with_log() {
  local bash_verdict="$1"
  local mcp_verdict="$2"
  local event_id="${3:-evt-001}"

  # JSONL 形式の shadow log を sandbox に作成
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
# Sample 1: bash=allow, mcp=allow → mismatch なし (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample1: bash=allow mcp=allow → mismatch なし (exit 0)" {
  # RED: mcp-shadow-compare.sh 未実装なら fail
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "allow" "allow" "evt-s1"
  [ "$status" -eq 0 ]
  # mismatch 出力がないこと
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 2: bash=block, mcp=block → mismatch なし (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample2: bash=block mcp=block → mismatch なし (exit 0)" {
  # RED: mcp-shadow-compare.sh 未実装なら fail
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "block" "block" "evt-s2"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 3: bash=allow, mcp=block → mismatch (exit 1, stderr に MISMATCH)
# ---------------------------------------------------------------------------

@test "AC5 sample3: bash=allow mcp=block → mismatch 検出 (exit 1, stderr に MISMATCH)" {
  # RED: mcp-shadow-compare.sh 未実装なら fail
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "allow" "block" "evt-s3"
  [ "$status" -eq 1 ]
  # stderr に MISMATCH が含まれること (bats の $output は stdout+stderr 混在)
  [[ "$output" == *"MISMATCH"* ]] || [[ "$stderr" == *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 4: bash=block, mcp=allow → mismatch (exit 1, stderr に MISMATCH)
# ---------------------------------------------------------------------------

@test "AC5 sample4: bash=block mcp=allow → mismatch 検出 (exit 1, stderr に MISMATCH)" {
  # RED: mcp-shadow-compare.sh 未実装なら fail
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_with_log "block" "allow" "evt-s4"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH"* ]] || [[ "$stderr" == *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# Sample 5: ログが空（0 件）→ mismatch なし (exit 0)
# ---------------------------------------------------------------------------

@test "AC5 sample5: ログが空 (0 件) → mismatch なし (exit 0)" {
  # RED: mcp-shadow-compare.sh 未実装なら fail
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  local log_file="$SANDBOX/deps-yaml-shadow-empty.log"
  # 空ファイルを作成
  : > "$log_file"
  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}
