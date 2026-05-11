#!/usr/bin/env bats
# spawn-feature-dev-mcp.bats - Issue #1644 GREEN テスト
#
# twl_spawn_feature_dev_handler が薄い wrapper として spawn-controller.sh feature-dev を呼ぶことを検証。
#
# Coverage:
#   - AC-2.1: wrapper が subprocess.run(["bash", spawn_controller_sh, "feature-dev", str(issue), ...]) を呼ぶ
#   - AC-2.3: wrapper 内で cld-spawn 直接呼び出しが行われない（skill prefix は bash 側で prepend）
#   - bug-1/2 regression: SPAWN_CONTROLLER_SCRIPT env override で stub に切り替え可能
#   - bug-3 regression: prompt prefix は wrapper が組み立てない（bash 側で組み立て）

load '../helpers/common'

SPAWN_CONTROLLER_STUB=""
SPAWN_CONTROLLER_ARGS_LOG=""
SUPERVISOR_DIR_TEST=""

setup() {
  common_setup

  SUPERVISOR_DIR_TEST="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR_TEST/consumed"
  export SUPERVISOR_DIR_TEST

  SPAWN_CONTROLLER_ARGS_LOG="$SANDBOX/spawn-controller-args.log"
  export SPAWN_CONTROLLER_ARGS_LOG

  # spawn-controller.sh stub: 引数を log に記録して成功を返す
  # NOTE: spawn-controller.sh は通常 "feature-dev <issue>" の形式で呼ばれる
  SPAWN_CONTROLLER_STUB="$SANDBOX/spawn-controller-stub.sh"
  cat > "$SPAWN_CONTROLLER_STUB" <<'STUB'
#!/usr/bin/env bash
# stub: 引数を log に記録、cld-spawn 風の出力を返す
echo "$@" >> "${SPAWN_CONTROLLER_ARGS_LOG:-/dev/null}"
echo "spawned → tmux window 'wt-fd-stub'"
exit 0
STUB
  chmod +x "$SPAWN_CONTROLLER_STUB"

  # tmux stub: display-message が session 名を返す
  cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "test-session"; exit 0 ;;
  list-panes) echo "12345"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"
}

teardown() {
  common_teardown
}

# Python handler を起動
_invoke_handler() {
  local issue="$1"
  local worktree_path="${2:-}"
  python3 - <<PYEOF
import json, os
os.environ['SPAWN_CONTROLLER_SCRIPT'] = '${SPAWN_CONTROLLER_STUB}'
from twl.mcp_server.tools import twl_spawn_feature_dev_handler
out = twl_spawn_feature_dev_handler(
    issue=${issue},
    worktree_path=$(if [[ -n "$worktree_path" ]]; then echo "'${worktree_path}'"; else echo "None"; fi),
    supervisor_dir='${SUPERVISOR_DIR_TEST}',
)
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ===========================================================================
# AC-2.1: wrapper が "bash spawn-controller.sh feature-dev <N>" を呼ぶ
# ===========================================================================

@test "mcp-wrapper: handler calls spawn-controller.sh feature-dev <issue>" {
  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true' >/dev/null || fail "ok != true: $output"

  local args
  args="$(cat "$SPAWN_CONTROLLER_ARGS_LOG")"
  [[ "$args" == *"feature-dev"* ]] || fail "feature-dev が渡されていない: $args"
  [[ "$args" == *"1644"* ]] || fail "issue number が渡されていない: $args"
}

# ===========================================================================
# AC-2.1: worktree_path → --cd <path>
# ===========================================================================

@test "mcp-wrapper: worktree_path → --cd <path>" {
  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644 "/tmp/test-worktree"
  [ "$status" -eq 0 ]
  local args
  args="$(cat "$SPAWN_CONTROLLER_ARGS_LOG")"
  [[ "$args" == *"--cd /tmp/test-worktree"* ]] \
    || fail "--cd /tmp/test-worktree が渡されていない: $args"
}

# ===========================================================================
# AC-2.1: model/timeout のデフォルト値が渡される
# ===========================================================================

@test "mcp-wrapper: model/timeout default args passed" {
  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644
  [ "$status" -eq 0 ]
  local args
  args="$(cat "$SPAWN_CONTROLLER_ARGS_LOG")"
  [[ "$args" == *"--model claude-opus-4-7"* ]] \
    || fail "--model claude-opus-4-7 が渡されていない: $args"
  [[ "$args" == *"--timeout 120"* ]] \
    || fail "--timeout 120 が渡されていない: $args"
}

# ===========================================================================
# AC-2.1: window/session が JSON で返る
# ===========================================================================

@test "mcp-wrapper: returns window/session JSON" {
  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.window' >/dev/null || fail "window が返されていない: $output"
  echo "$output" | jq -e '.session' >/dev/null || fail "session が返されていない: $output"
}

# ===========================================================================
# bug-1/2 regression: SPAWN_CONTROLLER_SCRIPT env で stub に切り替え可能
# ===========================================================================

@test "mcp-wrapper: SPAWN_CONTROLLER_SCRIPT env で stub に切り替え可能（bug-1/2 regression）" {
  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644
  [ "$status" -eq 0 ]
  # log が書かれたことを確認 = stub が呼ばれた = path resolution が成功
  [ -s "$SPAWN_CONTROLLER_ARGS_LOG" ] || fail "spawn-controller stub が呼ばれていない（path resolution 失敗の可能性）"
}

# ===========================================================================
# AC-2.3: cld-spawn 直接呼び出しが行われない (bug-3 regression)
# ===========================================================================

@test "mcp-wrapper: cld-spawn 直接呼び出しは無い（bug-3 regression）" {
  # cld-spawn stub を作って、呼ばれた場合に検出
  CLD_SPAWN_FLAG="$SANDBOX/cld-spawn-was-called.flag"
  cat > "$STUB_BIN/cld-spawn" <<STUB
#!/usr/bin/env bash
touch "${CLD_SPAWN_FLAG}"
exit 0
STUB
  chmod +x "$STUB_BIN/cld-spawn"

  > "$SPAWN_CONTROLLER_ARGS_LOG"
  run _invoke_handler 1644
  [ "$status" -eq 0 ]

  # cld-spawn が直接呼ばれていないこと（spawn-controller stub は cld-spawn を呼ばない）
  [ ! -f "$CLD_SPAWN_FLAG" ] || fail "cld-spawn が wrapper 経由で直接呼ばれた（bug-3 再発）"
}

# ===========================================================================
# AC-2.1: invalid issue (負数/0) → DENY
# ===========================================================================

@test "mcp-wrapper: invalid issue (0) → DENY" {
  run _invoke_handler 0
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == false' >/dev/null || fail "ok != false: $output"
  echo "$output" | jq -r '.error' | grep -qE "positive integer" \
    || fail "positive integer エラーが含まれない: $output"
}

# ===========================================================================
# AC-2.1: spawn-controller.sh が見つからない → DENY
# ===========================================================================

@test "mcp-wrapper: spawn-controller.sh not found → DENY" {
  python3 - <<PYEOF
import json, os, sys
os.environ['SPAWN_CONTROLLER_SCRIPT'] = '/nonexistent/path/spawn-controller.sh'
from twl.mcp_server.tools import twl_spawn_feature_dev_handler
out = twl_spawn_feature_dev_handler(
    issue=1644,
    supervisor_dir='${SUPERVISOR_DIR_TEST}',
)
assert out['ok'] is False, f"expected ok=False, got: {out}"
assert 'not found' in out['error'], f"expected 'not found' in error, got: {out['error']}"
print("OK")
PYEOF
}
