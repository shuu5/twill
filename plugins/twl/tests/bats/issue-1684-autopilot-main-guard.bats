#!/usr/bin/env bats
# issue-1684-autopilot-main-guard.bats
#
# Issue #1684: IS_AUTOPILOT=true worktree skip + orchestrator early-exit で
# Worker が main 直接動作する (P0 invariant K/L risk)
#
# AC1: IS_AUTOPILOT=true 時の worktree-create skip path 安全装置
# AC2: Worker の runtime cwd guard（main worktree なら abort）
# AC3: bats test (regression)
#   - IS_AUTOPILOT=true + worktree 存在 = success
#   - IS_AUTOPILOT=true + worktree 不在 = abort (新規 guard)
#   - Worker cwd=main = abort (新規 guard)
# AC4: window naming guard (autopilot-launch.sh で main branch 選択を error 化)

load 'helpers/common'

SCRIPTS_DIR=""
CHAIN_RUNNER=""
AUTOPILOT_LAUNCH=""

setup() {
  common_setup
  local bats_dir
  bats_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${bats_dir}/.." && pwd)"
  local plugin_root_dir
  plugin_root_dir="$(cd "${tests_dir}/.." && pwd)"
  SCRIPTS_DIR="${plugin_root_dir}/scripts"
  CHAIN_RUNNER="${SCRIPTS_DIR}/chain-runner.sh"
  AUTOPILOT_LAUNCH="${SCRIPTS_DIR}/autopilot-launch.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1/AC2: step_cwd_guard 関数が chain-runner.sh に存在する（static）
#
# RED: 現在 chain-runner.sh に step_cwd_guard 関数が存在しない
# GREEN: step_cwd_guard 実装後に PASS
# ===========================================================================

@test "ac1: chain-runner.sh に step_cwd_guard 関数が定義されている" {
  # AC: step_cwd_guard 関数が chain-runner.sh に存在する
  # RED: 現在は未実装
  run grep -q "step_cwd_guard" "${CHAIN_RUNNER}"
  assert_success
}

@test "ac1: chain-runner.sh に cwd-guard ディスパッチが存在する" {
  # AC: case ブロックに cwd-guard) エントリが存在する
  # RED: 現在は未実装
  run grep -q 'cwd-guard)' "${CHAIN_RUNNER}"
  assert_success
}

# ===========================================================================
# AC2: cwd-guard step — main ブランチなら exit 2 で abort（dynamic）
#
# RED: chain-runner.sh cwd-guard は現在「未知のステップ」で exit 1
# GREEN: step_cwd_guard 実装後、main ブランチで exit 2
# ===========================================================================

@test "ac2: cwd-guard step — main ブランチで exit 2 (abort)" {
  # git stub: main ブランチを返す
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "branch --show-current" ]]; then
  echo "main"
  exit 0
fi
# worktree list --porcelain など他の git コマンドはパススルー
exec /usr/bin/git "$@"
STUB
  chmod +x "$STUB_BIN/git"

  # python3 stub: autopilot state は running (IS_AUTOPILOT=true)
  cat > "$STUB_BIN/python3" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"autopilot.state"* ]]; then
  # state read → running
  echo "running"
  exit 0
fi
exec /usr/bin/python3 "$@"
STUB
  chmod +x "$STUB_BIN/python3"

  cd "$SANDBOX"
  # AUTOPILOT_DIR は common_setup で設定済み
  run bash "${CHAIN_RUNNER}" cwd-guard
  # main ブランチで abort → exit 2
  assert_failure
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "main"
}

@test "ac2: cwd-guard step — feature ブランチで success (exit 0)" {
  # git stub: feature ブランチを返す
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "branch --show-current" ]]; then
  echo "fix/1684-bugchain"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$STUB_BIN/git"

  cd "$SANDBOX"
  run bash "${CHAIN_RUNNER}" cwd-guard
  assert_success
}

@test "ac2: cwd-guard step — master ブランチでも exit 2 (abort)" {
  # git stub: master ブランチを返す（legacy repo 対応）
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "branch --show-current" ]]; then
  echo "master"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$STUB_BIN/git"

  cd "$SANDBOX"
  run bash "${CHAIN_RUNNER}" cwd-guard
  assert_failure
  [ "$status" -eq 2 ]
}

# ===========================================================================
# AC3 regression: IS_AUTOPILOT=true + worktree 存在 = success
#
# worktree-create step が IS_AUTOPILOT=true + 非 main ブランチで
# "既に worktree 内" skip メッセージを出力し exit 0 すること
# ===========================================================================

@test "ac3: worktree-create — IS_AUTOPILOT=true + feature worktree で success" {
  # git stub: feature ブランチを返す
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "branch --show-current" ]]; then
  echo "fix/1684-test-worktree"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$STUB_BIN/git"

  export IS_AUTOPILOT=true
  cd "$SANDBOX"
  run bash "${CHAIN_RUNNER}" worktree-create "#1684"
  assert_success
  echo "$output" | grep -qi "スキップ"
}

# ===========================================================================
# AC3 regression: IS_AUTOPILOT=true + worktree 不在 (main ブランチ) = abort
#
# setup chain が main ブランチで実行された場合、source-touching step の前に
# cwd-guard が abort すること（新規 guard）
# ===========================================================================

@test "ac3: cwd-guard — IS_AUTOPILOT=true + main ブランチで abort (exit 2)" {
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "branch --show-current" ]]; then
  echo "main"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$STUB_BIN/git"

  export IS_AUTOPILOT=true
  cd "$SANDBOX"
  run bash "${CHAIN_RUNNER}" cwd-guard
  assert_failure
  [ "$status" -eq 2 ]
}

# ===========================================================================
# AC4: autopilot-launch.sh に main branch LAUNCH_DIR バリデーションが存在する
#
# bare repo で worktree 作成失敗時、main/ fallback への分岐を error 化するガードが
# autopilot-launch.sh に存在すること
#
# RED: 現在 autopilot-launch.sh は main/ fallback を警告なしで許可している
# GREEN: main/ fallback を error 化するガード追加後に PASS
# ===========================================================================

@test "ac4: autopilot-launch.sh に main ブランチ LAUNCH_DIR バリデーションが存在する" {
  # AC: autopilot-launch.sh が LAUNCH_DIR=main/ を error として扱うガードを持つ
  # RED: 現在は fallback として main/ を許可している
  run grep -qE 'main.*ERROR|ERROR.*main|launch_dir.*main.*abort|main.*invariant' "${AUTOPILOT_LAUNCH}"
  assert_success
}

@test "ac4: autopilot-launch.sh の main fallback path が error 化されている" {
  # AC: "fallback: bare repo で worktree 作成失敗時は main/ で起動" のコメント行が
  # error 処理に変更されている（または削除されている）
  # RED: 現在は LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR/main" という fallback が存在する
  run bash -c "grep -q 'fallback.*bare.*main' '${AUTOPILOT_LAUNCH}' && grep '# fallback.*bare.*main' '${AUTOPILOT_LAUNCH}' | grep -v 'error\|ERROR\|abort\|abort'"
  # GREEN 後: fallback コメントが error ハンドリングに置き換わっているため、
  # "fallback" コメントを grep して error/abort パターンが一緒にあること
  # このテストは「fallback が警告なし」の場合に FAIL する設計
  assert_failure
}

# ===========================================================================
# AC4: window naming guard (static) — autopilot-launch.sh に
# window name に "main" が含まれるケースを block するコードが存在する
# ===========================================================================

@test "ac4: autopilot-launch.sh に window name main ブロックガードが存在する" {
  # AC: LAUNCH_DIR が main/ を指す場合に abort するガードが存在する
  # guard パターン: LAUNCH_DIR ends in /main かつ exit or error を含む行
  # RED: 現在はガードなし（fallback として main/ を許可）
  run grep -qE 'LAUNCH_DIR.*main.*exit [12]|main.*\bLAUNCH_DIR\b.*invariant|_launch_dir_main_guard|main_launch_guard' "${AUTOPILOT_LAUNCH}"
  assert_success
}
