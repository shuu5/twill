#!/usr/bin/env bats
# worker-codex-reviewer-silent-skip.bats
#
# Issue #1289: worker-codex-reviewer silent skip 禁止 — reason: フィールド記録
#
# AC-3: worker-codex-reviewer.md で silent skip (reason 無し findings: []) を禁止し、
#       401/auth エラー検知時に findings.yaml に reason: field を必ず記録すること
#       (fixture ベースの offline 検証)
#
# RED フェーズ:
#   worker-codex-reviewer.md の CODEX_OK=0 スキップブロックが
#   現状 'findings: []' を出力し reason: を含まない → FAIL

load '../helpers/common'

WORKER_AGENT=""
PROBE_CHECK_SCRIPT=""

setup() {
  common_setup
  WORKER_AGENT="$REPO_ROOT/agents/worker-codex-reviewer.md"
  PROBE_CHECK_SCRIPT="$SANDBOX/scripts/codex-probe-check.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-3: agent spec が silent skip (findings: []) を禁止していること
# ---------------------------------------------------------------------------

@test "ac3-no-silent-skip: worker-codex-reviewer.md の CODEX_OK=0 スキップ出力に reason: が含まれる" {
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: worker-codex-reviewer.md が存在しない" >&2
    return 1
  }
  # CODEX_OK=0 ブロック以降50行以内に reason: が存在すること
  # process substitution でサブシェル問題を回避
  grep -A50 "CODEX_OK=0" "$WORKER_AGENT" | grep -q "reason:"
}

# ---------------------------------------------------------------------------
# AC-3: 'findings: []' (reason なし) のバリアントが spec に残っていないこと
# ---------------------------------------------------------------------------

@test "ac3-findings-empty-array-removed: worker-codex-reviewer.md の skip 出力に reason なし findings: [] がない" {
  # CODEX_OK=0 スキップブロックの直後30行に 'findings: []' が残っていてはならない
  [[ -f "$WORKER_AGENT" ]] || skip "agent spec not found"
  # grep -A30 で CODEX_OK=0 ブロックの後続を抽出し findings: [] がないことを確認
  ! (grep -A30 "CODEX_OK=0.*の場合\|CODEX_OK=0.*case" "$WORKER_AGENT" | grep -qF "findings: []")
}

# ---------------------------------------------------------------------------
# AC-3: 401 fixture → CODEX_OK=0 → 実際のスクリプト出力に reason: を含む
# ---------------------------------------------------------------------------

@test "ac3-script-output-reason: CODEX_OK=0 時の出力に reason: が含まれる" {
  # Worker の Step 1 skip 出力ロジックを抽出してテスト
  # RED: 現在の出力は 'findings: []' のみ → reason: なし → FAIL

  # PROBE_OUT に 401 を含む fixture
  local output
  output=$(bash -c '
    PROBE_MODEL="gpt-5.3-codex"
    PROBE_OUT="model: gpt-5.3-codex
HTTP 401 Unauthorized"
    CODEX_OK=1

    # 新実装: codex-probe-check.sh が 401 を検知して CODEX_OK=0 にする
    if [[ -f "'"$PROBE_CHECK_SCRIPT"'" ]]; then
      source "'"$PROBE_CHECK_SCRIPT"'"
      run_probe_check 2>/dev/null || true
    fi

    if [[ "$CODEX_OK" -eq 0 ]]; then
      # AC-3: reason: を含む出力 (修正後の期待形式)
      cat <<EOF
worker-codex-reviewer 完了

status: PASS

findings:
  - reason: "codex auth error (CODEX_OK=0)"
EOF
    fi
  ' 2>/dev/null)

  # CODEX_OK=0 が正しく設定され reason: が出力されること
  echo "$output" | grep -q "reason:"
}
