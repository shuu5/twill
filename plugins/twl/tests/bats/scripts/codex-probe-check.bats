#!/usr/bin/env bats
# codex-probe-check.bats
#
# Issue #1289: worker-codex-reviewer silent skip — 401 stderr 検知
#
# AC-1: run_probe_check() が probe stderr の 401|Unauthorized|connection refused|websocket
#       パターンを検知して CODEX_OK=0 を返すこと。probe capture の head -5 を head -20 に増加。
# AC-2: 各 fixture (401/Unauthorized/connection refused/websocket) で CODEX_OK=0 を assert
#       (fixture ファイルベースのオフラインテスト)
#
# RED フェーズ:
#   run_probe_check() に 401 検知ロジック未実装のため、
#   "model: 行あり + auth エラー" フィクスチャは現状 CODEX_OK=1 のまま → FAIL
#   worker-codex-reviewer.md に head -5 が残っている → FAIL

load '../helpers/common'

PROBE_CHECK_SCRIPT=""
WORKER_AGENT=""

setup() {
  common_setup
  PROBE_CHECK_SCRIPT="$SANDBOX/scripts/codex-probe-check.sh"
  WORKER_AGENT="$REPO_ROOT/agents/worker-codex-reviewer.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-1: probe capture の head -5 → head -20 変更確認
# ---------------------------------------------------------------------------

@test "ac1-head20: worker-codex-reviewer.md の probe capture が head -20 を使用する" {
  # RED: head -5 が残っているため FAIL
  [[ -f "$WORKER_AGENT" ]] || {
    echo "FAIL: worker-codex-reviewer.md が存在しない" >&2
    return 1
  }
  # head -5 が残っていてはならない (head -20 に変更済みであるべき)
  ! grep -qF "head -5" "$WORKER_AGENT"
}

# ---------------------------------------------------------------------------
# AC-2: 401 fixture — model 行あり、PROBE_OUT に 401 エラーを含む
# ---------------------------------------------------------------------------

@test "ac2-401: model 行あり + PROBE_OUT に 401 を含む場合 CODEX_OK=0 になる" {
  # RED: run_probe_check() に 401 検知ロジック未実装のため CODEX_OK=1 のまま → FAIL
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Connecting to wss://api.openai.com/v1/responses...
HTTP 401 Unauthorized"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-2: Unauthorized fixture — model 行あり
# ---------------------------------------------------------------------------

@test "ac2-unauthorized: model 行あり + PROBE_OUT に Unauthorized を含む場合 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: 401 Unauthorized — API key lacks Responses API scope"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-2: connection refused fixture
# ---------------------------------------------------------------------------

@test "ac2-connection-refused: model 行あり + connection refused 時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
Error: connect ECONNREFUSED 127.0.0.1:443 - connection refused"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-2: websocket fixture
# ---------------------------------------------------------------------------

@test "ac2-websocket: model 行あり + websocket エラー時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
WebSocket error: failed to connect to wss://api.openai.com/v1/responses"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC-1: non-regression — 401 パターンなしの正常出力では CODEX_OK を変更しない
# ---------------------------------------------------------------------------

@test "ac1-non-regression: 正常な probe 出力では CODEX_OK=1 のまま" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="model: gpt-5.3-codex
output: Hello, world!"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# AC-2: 複合エラー fixture — model 行なし + 401 (既存 mismatch チェックとの OR 確認)
# ---------------------------------------------------------------------------

@test "ac2-401-no-model-line: model 行なし + 401 エラー時 CODEX_OK=0 になる" {
  PROBE_MODEL="gpt-5.3-codex"
  PROBE_OUT="HTTP 401 Unauthorized
wss://api.openai.com/v1/responses: 401"
  CODEX_OK=1
  source "$PROBE_CHECK_SCRIPT"
  run_probe_check
  [[ "$CODEX_OK" -eq 0 ]]
}
