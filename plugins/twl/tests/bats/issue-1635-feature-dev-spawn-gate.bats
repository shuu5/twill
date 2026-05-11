#!/usr/bin/env bats
# issue-1635-feature-dev-spawn-gate.bats
# Tests for Issue #1635: feat(supervision): observer feature-dev spawn gate
#
# AC coverage:
#   AC1 - 新 MCP tool twl_spawn_feature_dev の骨格実装
#   AC2 - 承認証跡ファイルの schema 定義と検証
#   AC3 - Status=Refined 検証（Phase 1: 4-stage taxonomy ベース）
#   AC4 - 承認証跡の one-shot 消費 + 並列 spawn check 統合
#   AC6 - SKIP_LAYER2=1 path に deprecation warning
#   AC7 - bats tests (RED → GREEN)
#
# テスト設計:
#   - Python handler を python3 -c で起動し JSON 戻り値を assert（PYTHONPATH は common_setup 設定）
#   - spawn-controller.sh の bash 側機能 (--check-parallel-only, SKIP_LAYER2 deprecation) も verify
#   - cld-spawn, tmux, gh はすべて stub_command で mock

load 'helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # 実スクリプトを直接呼ぶ（ファイルパス解決のため sandbox copy ではなく REPO_ROOT 経由）
  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  SUPERVISOR_DIR_TEST="${SANDBOX}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR_TEST}/consumed"

  export SPAWN_SCRIPT SUPERVISOR_DIR_TEST

  # cld-spawn stub: 成功 + window 名出力
  stub_command "cld-spawn" "echo \"spawned → tmux window 'wt-fd-stub'\"; exit 0"

  # tmux stub: display-message / list-panes は確定値
  cat > "$STUB_BIN/tmux" <<'STUB_EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "test-session"; exit 0 ;;
  list-panes) echo "12345"; exit 0 ;;
  *) exit 0 ;;
esac
STUB_EOF
  chmod +x "$STUB_BIN/tmux"

  # gh stub: Status=Refined を返す（個別テストで上書き可）
  cat > "$STUB_BIN/gh" <<'STUB_EOF'
#!/usr/bin/env bash
if echo "$*" | grep -q "project item-list"; then
  echo '{"items":[{"status":"Refined","content":{"number":1635}}]}'
  exit 0
fi
exit 0
STUB_EOF
  chmod +x "$STUB_BIN/gh"

  export TWL_BOARD_NUMBER=1
  export TWL_BOARD_OWNER=shuu5
  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats issue-1635 test"
  export SPAWN_CONTROLLER_SCRIPT="${SPAWN_SCRIPT}"
  # NOTE: SUPERVISOR_DIR は spawn-controller.sh で「絶対パス禁止」なので export しない。
  # Python handler は引数 supervisor_dir= で受け取り、内部で subprocess に渡す際に
  # cwd と相対パスを適切に組み合わせる。

  PROMPT_TEXT="test feature-dev prompt for #1635"
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# 承認証跡 JSON を書き出す
# Usage: _write_request <issue> [requested_at] [ttl_seconds] [extra_jq_filter]
_write_request() {
  local issue="$1"
  local requested_at="${2:-$NOW}"
  local ttl="${3:-1800}"
  local extra_jq="${4:-.}"
  local target="${SUPERVISOR_DIR_TEST}/feature-dev-request-${issue}.json"
  jq -n \
    --argjson issue "$issue" \
    --arg requested_at "$requested_at" \
    --argjson ttl "$ttl" \
    '{
      issue: $issue,
      requested_at: $requested_at,
      requested_by: "user",
      ttl_seconds: $ttl,
      intervention_id: "bats-uuid-1635",
      notes: "bats test approval"
    }' \
    | jq "$extra_jq" \
    > "$target"
}

# Python handler を起動して JSON を返す
_invoke_handler() {
  local issue="$1"
  python3 - <<PYEOF
import json, os
os.environ['SPAWN_CONTROLLER_SCRIPT'] = '${SPAWN_SCRIPT}'
# stub cld-spawn を Python handler に教える（_CLD_SPAWN_SCRIPT は cli/plugins/... に
# 誤解決される既知の latent bug あり、env override で回避）
os.environ['CLD_SPAWN_SCRIPT'] = '${STUB_BIN}/cld-spawn'
os.environ['TWL_BOARD_NUMBER'] = '${TWL_BOARD_NUMBER:-1}'
os.environ['TWL_BOARD_OWNER'] = '${TWL_BOARD_OWNER:-shuu5}'
# SUPERVISOR_DIR は handler に supervisor_dir= 引数で渡す（絶対パス可）。
# subprocess 呼び出し時は handler 側で cwd + relative SUPERVISOR_DIR を組み立てる。
from twl.mcp_server.tools import twl_spawn_feature_dev_handler
out = twl_spawn_feature_dev_handler(
    issue=${issue},
    prompt_text="""${PROMPT_TEXT}""",
    supervisor_dir='${SUPERVISOR_DIR_TEST}',
)
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ===========================================================================
# AC2: 承認証跡ファイル不在 → DENY
# ===========================================================================

@test "ac2: approval trail not found → DENY" {
  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  # error メッセージに 'request file not found' を含む
  echo "$output" | jq -r '.error' | grep -qE "request file not found"
}

# ===========================================================================
# AC2: TTL 切れ → DENY
# ===========================================================================

@test "ac2: TTL expired → DENY" {
  # requested_at = 2 時間前、TTL = 1800s (30 分) → expired
  local past
  past=$(python3 -c "import datetime; print((datetime.datetime.utcnow()-datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  _write_request 1635 "$past" 1800

  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  echo "$output" | jq -r '.error' | grep -qE "TTL expired"
}

# ===========================================================================
# AC2: schema 違反（required field 欠落）→ DENY
# ===========================================================================

@test "ac2: schema missing field → DENY" {
  # ttl_seconds を削除
  _write_request 1635 "$NOW" 1800 "del(.ttl_seconds)"
  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  echo "$output" | jq -r '.error' | grep -qE "missing field"
}

# ===========================================================================
# AC3: Status != Refined → DENY
# ===========================================================================

@test "ac3: Status != Refined → DENY" {
  # gh stub を Status=Todo を返すように上書き
  cat > "$STUB_BIN/gh" <<'STUB_EOF'
#!/usr/bin/env bash
if echo "$*" | grep -q "project item-list"; then
  echo '{"items":[{"status":"Todo","content":{"number":1635}}]}'
  exit 0
fi
exit 0
STUB_EOF
  chmod +x "$STUB_BIN/gh"

  _write_request 1635 "$NOW" 1800

  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  echo "$output" | jq -r '.error' | grep -qE "Status must be Refined"
}

# ===========================================================================
# AC1+AC4: 全 check pass → cld-spawn 呼び出し + consumed/ への move
# ===========================================================================

@test "ac1+4: all checks pass → cld-spawn invoked, approval consumed" {
  _write_request 1635 "$NOW" 1800

  # 事前: 承認証跡が存在
  [ -f "${SUPERVISOR_DIR_TEST}/feature-dev-request-1635.json" ]

  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true' >/dev/null
  echo "$output" | jq -e '.error == null' >/dev/null
  # window 名が返る
  echo "$output" | jq -e '.window != null' >/dev/null

  # 事後: 承認証跡が消滅
  [ ! -f "${SUPERVISOR_DIR_TEST}/feature-dev-request-1635.json" ]

  # consumed/ 配下に移動済
  local consumed_count
  consumed_count=$(find "${SUPERVISOR_DIR_TEST}/consumed" -name "feature-dev-request-1635-*.json" | wc -l)
  [ "$consumed_count" -ge 1 ]
}

# ===========================================================================
# AC4: one-shot 消費（2 回目は DENY）
# ===========================================================================

@test "ac4: one-shot consume — second call denied" {
  _write_request 1635 "$NOW" 1800

  # 1 回目: 成功
  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true' >/dev/null

  # 2 回目: 承認証跡が消滅しているため DENY
  run _invoke_handler 1635
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  echo "$output" | jq -r '.error' | grep -qE "request file not found"
}

# ===========================================================================
# AC6: SKIP_LAYER2=1 path に deprecation warning が出力される
# ===========================================================================

@test "ac6: SKIP_LAYER2=1 emits DEPRECATION warning" {
  echo "test prompt" > "${SANDBOX}/test-prompt.txt"
  mkdir -p "${SANDBOX}/.supervisor"
  cd "${SANDBOX}"
  # SUPERVISOR_DIR を相対指定（".supervisor"）として spawn-controller の検証を pass させる
  run env SKIP_LAYER2=1 SKIP_LAYER2_REASON="bats test" \
    SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="bats test" \
    SUPERVISOR_DIR=".supervisor" \
    bash "${SPAWN_SCRIPT}" feature-dev "${SANDBOX}/test-prompt.txt" 2>&1
  [ "$status" -eq 0 ]
  # DEPRECATION warning が含まれる
  echo "$output" | grep -qi "DEPRECATION"
  echo "$output" | grep -q "mcp__twl__twl_spawn_feature_dev"
}

# ===========================================================================
# AC4: --check-parallel-only サブコマンド（SKIP_PARALLEL_CHECK=1 で exit 0）
# ===========================================================================

@test "ac4: --check-parallel-only exits successfully when SKIP_PARALLEL_CHECK=1" {
  mkdir -p "${SANDBOX}/.supervisor"
  cd "${SANDBOX}"
  run env SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="bats test" \
    SUPERVISOR_DIR=".supervisor" \
    bash "${SPAWN_SCRIPT}" --check-parallel-only 1635 2>&1
  [ "$status" -eq 0 ]
}
