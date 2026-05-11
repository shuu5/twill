#!/usr/bin/env bats
# spawn-controller-feature-dev.bats - Issue #1644 GREEN テスト
#
# Coverage:
#   - feature-dev skill prefix prepend (/feature-dev:feature-dev #<N>) (AC-1.2)
#   - feature-dev path への引数インタフェース拡張（issue-number）(AC-1.2)
#   - 承認証跡 gate: missing/TTL/schema (AC-1.3)
#   - 承認証跡 gate: pass → atomic rename to consumed/ (AC-1.3)
#   - cross-fs fallback (cp + rm) (AC-1.3)
#   - SKIP_LAYER2=1 で gate bypass (AC-4.6)
#   - window name wt-fd-<N> 自動生成
#   - provenance 注入
#   - MUST prompt 注入 (AC-3.2)
#
# 設計:
#   - 実 spawn-controller.sh を直接呼ぶ（TWILL_ROOT が正しく解決されるため）
#   - CLD_SPAWN_OVERRIDE env var で cld-spawn をスタブに切り替え（#1644 で導入）

load '../helpers/common'

SPAWN_CONTROLLER=""
CLD_SPAWN_ARGS_LOG=""
MOCK_CLD_SPAWN=""
SUPERVISOR_DIR_TEST=""
NOW=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  SUPERVISOR_DIR_TEST="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR_TEST/consumed"
  export SUPERVISOR_DIR_TEST

  # cld-spawn stub: 引数を log に記録して 0 exit
  MOCK_CLD_SPAWN="$STUB_BIN/cld-spawn"
  cat > "$MOCK_CLD_SPAWN" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
echo "spawned → tmux window 'wt-fd-stub'"
exit 0
MOCK
  chmod +x "$MOCK_CLD_SPAWN"
  export CLD_SPAWN_OVERRIDE="$MOCK_CLD_SPAWN"

  # tmux stub
  cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "test-session"; exit 0 ;;
  list-panes) echo "12345"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # gh stub: 既定 Status=Refined（個別テストで上書き可）
  cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
if echo "$*" | grep -q "project item-list"; then
  echo '{"items":[{"status":"Refined","content":{"number":1644}}]}'
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/gh"

  export TWL_BOARD_NUMBER=1
  export TWL_BOARD_OWNER=shuu5
  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats test"
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

teardown() {
  common_teardown
}

# 承認証跡 JSON を書き出す
_write_request() {
  local issue="$1"
  local requested_at="${2:-$NOW}"
  local ttl="${3:-1800}"
  local extra_jq="${4:-.}"
  local target="$SUPERVISOR_DIR_TEST/feature-dev-request-${issue}.json"
  jq -n \
    --argjson issue "$issue" \
    --arg requested_at "$requested_at" \
    --argjson ttl "$ttl" \
    '{
      issue: $issue,
      requested_at: $requested_at,
      requested_by: "user",
      ttl_seconds: $ttl,
      intervention_id: "bats-uuid-1644",
      notes: "bats test approval"
    }' \
    | jq "$extra_jq" \
    > "$target"
}

# feature-dev 起動を実行（cd して相対 SUPERVISOR_DIR を有効化）
_run_feature_dev() {
  local issue="$1"
  shift
  local cd_path="$SANDBOX/_existing_worktree"
  mkdir -p "$cd_path"
  cd "$SANDBOX"
  env SUPERVISOR_DIR=".supervisor" \
      SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="bats test" \
      bash "$SPAWN_CONTROLLER" feature-dev "$issue" --cd "$cd_path" "$@" 2>&1
}

# ===========================================================================
# AC-1.2: skill prefix /feature-dev:feature-dev #<N>
# ===========================================================================

@test "fd-prefix: /feature-dev:feature-dev #<N> prefix が cld-spawn に渡る" {
  _write_request 1644
  > "$CLD_SPAWN_ARGS_LOG"

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"/feature-dev:feature-dev #1644"* ]] \
    || fail "cld-spawn 引数に /feature-dev:feature-dev #1644 が含まれない: $args"
  # /twl:feature-dev は使われないことを確認
  [[ "$args" != *"/twl:feature-dev"* ]] \
    || fail "誤った /twl:feature-dev prefix が含まれる: $args"
}

@test "fd-prefix: window-name 自動生成は wt-fd-<N>" {
  _write_request 1644
  > "$CLD_SPAWN_ARGS_LOG"

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"--window-name wt-fd-1644"* ]] \
    || fail "wt-fd-1644 が含まれない: $args"
}

# ===========================================================================
# AC-1.2: 引数バリデーション
# ===========================================================================

@test "fd-args: invalid issue number → exit 2" {
  cd "$SANDBOX"
  mkdir -p "$SUPERVISOR_DIR_TEST"
  run env SUPERVISOR_DIR=".supervisor" \
    bash "$SPAWN_CONTROLLER" feature-dev "abc" 2>&1
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer issue number"* ]] \
    || fail "issue number エラーメッセージが出ない: $output"
}

# ===========================================================================
# AC-1.3: Gate checks — approval file 不在 → DENY
# ===========================================================================

@test "fd-gate: approval trail not found → DENY (exit 1)" {
  # 承認証跡を書かない
  run _run_feature_dev 1644
  [ "$status" -eq 1 ]
  [[ "$output" == *"approval trail not found"* ]] \
    || fail "approval trail not found エラーが出ない: $output"
}

# ===========================================================================
# AC-1.3: Gate checks — TTL 切れ → DENY
# ===========================================================================

@test "fd-gate: TTL expired → DENY (exit 1)" {
  local past
  past=$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  _write_request 1644 "$past" 1800

  run _run_feature_dev 1644
  [ "$status" -eq 1 ]
  [[ "$output" == *"TTL expired"* ]] \
    || fail "TTL expired エラーが出ない: $output"
}

# ===========================================================================
# AC-1.3: Gate checks — schema 違反 → DENY
# ===========================================================================

@test "fd-gate: schema missing field → DENY (exit 1)" {
  _write_request 1644 "$NOW" 1800 "del(.ttl_seconds)"
  run _run_feature_dev 1644
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing field"* ]] \
    || fail "missing field エラーが出ない: $output"
}

# ===========================================================================
# AC-1.3: Gate checks — pass + atomic rename
# ===========================================================================

@test "fd-gate: all pass → approval consumed to consumed/" {
  _write_request 1644

  # 事前: 承認証跡が存在
  [ -f "$SUPERVISOR_DIR_TEST/feature-dev-request-1644.json" ]

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }

  # 事後: 承認証跡は消滅
  [ ! -f "$SUPERVISOR_DIR_TEST/feature-dev-request-1644.json" ]

  # consumed/ に move 済み
  local count
  count=$(find "$SUPERVISOR_DIR_TEST/consumed" -name "feature-dev-request-1644-*.json" | wc -l)
  [ "$count" -ge 1 ]
}

# ===========================================================================
# AC-1.3: one-shot consume (2 回目は DENY)
# ===========================================================================

@test "fd-gate: one-shot consume — 2nd call denied" {
  _write_request 1644

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "first call output: $output"; false; }

  # 2 回目: approval trail not found
  run _run_feature_dev 1644
  [ "$status" -eq 1 ]
  [[ "$output" == *"approval trail not found"* ]] \
    || fail "2nd call で approval not found エラーが出ない: $output"
}

# ===========================================================================
# AC-1.3: cross-filesystem fallback (cp + rm)
# ===========================================================================

@test "fd-gate: cross-fs fallback — mv が cross-device error を返した場合 cp+rm にフォールバック" {
  _write_request 1644

  # mv stub: cross-device error を返す（-n flag 検出のみ）
  cat > "$STUB_BIN/mv" <<'MV_STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "-n" ]]; then
    echo "mv: cannot move 'X' to 'Y': Invalid cross-device link" >&2
    exit 1
  fi
done
exec /bin/mv "$@"
MV_STUB
  chmod +x "$STUB_BIN/mv"

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }

  # consumed/ に move されていること（cp+rm fallback による）
  local count
  count=$(find "$SUPERVISOR_DIR_TEST/consumed" -name "feature-dev-request-1644-*.json" | wc -l)
  [ "$count" -ge 1 ]
  # 元ファイル消滅
  [ ! -f "$SUPERVISOR_DIR_TEST/feature-dev-request-1644.json" ]
}

# ===========================================================================
# AC-4.6: SKIP_LAYER2=1 で gate bypass
# ===========================================================================

@test "fd-skip-layer2: SKIP_LAYER2=1 で gate bypass — 承認証跡無しでも spawn 成功" {
  # 承認証跡を書かない
  > "$CLD_SPAWN_ARGS_LOG"
  local cd_path="$SANDBOX/_existing_worktree"
  mkdir -p "$cd_path"
  cd "$SANDBOX"

  run env SUPERVISOR_DIR=".supervisor" \
    SKIP_LAYER2=1 SKIP_LAYER2_REASON="bats test bypass" \
    SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="bats test" \
    bash "$SPAWN_CONTROLLER" feature-dev 1644 --cd "$cd_path" 2>&1
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  [[ "$output" == *"SKIP_LAYER2=1"* ]] \
    || fail "SKIP_LAYER2 警告メッセージが出ない: $output"

  # cld-spawn は呼び出される
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"/feature-dev:feature-dev #1644"* ]] \
    || fail "SKIP_LAYER2 bypass でも cld-spawn が正しく呼ばれていない: $args"
}

# ===========================================================================
# AC-3.2: MUST prompt 注入 (main 直接 push 禁止 / worktree 内作業)
# ===========================================================================

@test "fd-must-prompt: prompt 末尾に MUST 注入が含まれる" {
  _write_request 1644
  > "$CLD_SPAWN_ARGS_LOG"

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"MUST: worktree 内"* ]] \
    || fail "MUST worktree 注入が含まれない: $args"
  [[ "$args" == *"main への直接 push は禁止"* ]] \
    || fail "main push 禁止注入が含まれない: $args"
}

# ===========================================================================
# provenance 注入: ## provenance (auto-injected) ヘッダー
# ===========================================================================

@test "fd-provenance: cld-spawn 引数に provenance section が含まれる" {
  _write_request 1644
  > "$CLD_SPAWN_ARGS_LOG"

  run _run_feature_dev 1644
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"## provenance (auto-injected)"* ]] \
    || fail "provenance ヘッダーが含まれない: $args"
}

# ===========================================================================
# AC-1.6 (既存 6 controller の動作不変)
# 単純 sanity check: co-explore を spawn-controller.sh で起動して /twl:co-explore prefix が付くこと
# ===========================================================================

@test "fd-regress: 既存 6 controller (co-explore) は /twl: prefix のまま動作不変" {
  echo "regression test prompt" > "$SANDBOX/prompt.txt"
  > "$CLD_SPAWN_ARGS_LOG"
  cd "$SANDBOX"
  mkdir -p "$SUPERVISOR_DIR_TEST"

  run env SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 SKIP_PARALLEL_REASON="bats regression" \
    bash "$SPAWN_CONTROLLER" co-explore "$SANDBOX/prompt.txt" \
    --window-name "test-window" 2>&1
  [ "$status" -eq 0 ] || { echo "output: $output"; false; }
  local args
  args="$(cat "$CLD_SPAWN_ARGS_LOG")"
  [[ "$args" == *"/twl:co-explore"* ]] \
    || fail "co-explore で /twl:co-explore prefix が付かない: $args"
}
