#!/usr/bin/env bats
# autopilot-launch-autopilotdir.bats
# Unit/integration tests for AUTOPILOT_DIR env propagation in autopilot-launch.sh
#
# Spec: deltaspec/changes/issue-478/specs/autopilotdir-env-propagation/spec.md
#
# Coverage:
#   Scenario 1: カスタム AUTOPILOT_DIR が Worker 起動コマンドに渡される
#     WHEN --autopilot-dir /tmp/custom-dir を指定して autopilot-launch.sh を起動する
#     THEN Worker 起動コマンド（tmux new-window の引数）に AUTOPILOT_DIR=/tmp/custom-dir が含まれている
#
#   Scenario 2: デフォルト AUTOPILOT_DIR が PROJECT_ROOT/.autopilot にフォールバックする
#     WHEN AUTOPILOT_DIR 環境変数を設定せず autopilot-init.sh を起動する
#     THEN $PROJECT_ROOT/.autopilot にディレクトリが作成される
#     NOTE: autopilotdir-state-split.bats の "AUTOPILOT_DIR override: default fallback uses PROJECT_ROOT/.autopilot"
#           と重複しないよう、こちらは autopilot-init.sh の具体的な出力内容に焦点を当てる
#
#   Scenario 3: AUTOPILOT_DIR カスタム設定時に state ファイルが指定パスに書かれる
#     WHEN AUTOPILOT_DIR=/tmp/foo を設定した状態で state write --type issue --issue N を実行する
#     THEN state ファイルが /tmp/foo/issues/issue-N.json に作成される
#     THEN $PROJECT_ROOT/.autopilot/issues/issue-N.json は作成されない
#
# Edge cases:
#   - AUTOPILOT_DIR に空白を含むパスを指定した場合でも正しくクォートされること
#   - AUTOPILOT_DIR が絶対パスでない場合はエラーになること
#   - AUTOPILOT_DIR にパストラバーサル（/../）を含む場合はエラーになること
#   - --autopilot-dir 未指定時はエラーになること
#   - 異なる issue 番号で state write した場合、各自の AUTOPILOT_DIR のみに書かれること
#
# 注記:
#   autopilot-launch.sh は printf '%q' で AUTOPILOT_DIR をシェルエスケープして
#   tmux new-window に渡す。そのためアサーションは tr -d '\\' で
#   バックスラッシュを除去してから grep -qF で検索する。

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # tmux スタブ: new-window の起動コマンドを TMUX_CMD_FILE に記録する
  TMUX_CMD_FILE="$SANDBOX/tmux-new-window.txt"
  export TMUX_CMD_FILE
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  new-window)
    printf '%s\n' "\$*" >> "${TMUX_CMD_FILE}"
    exit 0 ;;
  set-option|set-hook|display-message|list-windows)
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # cld スタブ
  cat > "$STUB_BIN/cld" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_BIN/cld"

  # gh スタブ: quick ラベルなし（デフォルト）
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*"--jq"*)
        echo "" ;;
      *)
        echo "{}" ;;
    esac
  '

  # git スタブ
  stub_command "git" '
    case "$*" in
      *"rev-parse"*) echo "$SANDBOX" ;;
      *"worktree list"*) echo "" ;;
      *) exit 0 ;;
    esac
  '

  # python3 スタブ: state write/read を無害化、worktree create は失敗させる
  cat > "$STUB_BIN/python3" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"worktree create"*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/python3"

  # テスト対象のプロジェクトディレクトリ（standard repo として扱う）
  mkdir -p "$SANDBOX/project/.git"
  TEST_PROJECT_DIR="$SANDBOX/project"
  export TEST_PROJECT_DIR

  # カスタム AUTOPILOT_DIR（テスト固有のパス）
  CUSTOM_AUTOPILOT_DIR="$SANDBOX/custom-autopilot"
  export CUSTOM_AUTOPILOT_DIR

  # session.json を CUSTOM_AUTOPILOT_DIR に用意
  mkdir -p "$CUSTOM_AUTOPILOT_DIR/trace"
  cat > "$CUSTOM_AUTOPILOT_DIR/session.json" <<JSON
{"session_id": "test-session-478", "started_at": "2026-04-10T00:00:00Z"}
JSON
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------

# autopilot-launch.sh を実行してtmux new-windowコマンドを記録する
_run_launch() {
  local issue="${1:-42}"
  local autopilot_dir="${2:-$CUSTOM_AUTOPILOT_DIR}"
  local extra_args="${3:-}"
  # shellcheck disable=SC2086
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue" \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "$autopilot_dir" \
    $extra_args
}

# tmux new-window コマンド全体を返す
_get_tmux_cmd() {
  cat "$TMUX_CMD_FILE" 2>/dev/null || echo ""
}

# tmux コマンド内に指定キーワードが含まれるか確認
# printf '%q' によるバックスラッシュエスケープを除去してから検索する
_tmux_cmd_contains() {
  local keyword="$1"
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "$keyword"
}

# ---------------------------------------------------------------------------
# Scenario 1: カスタム AUTOPILOT_DIR が Worker 起動コマンドに渡される
# ---------------------------------------------------------------------------

# WHEN --autopilot-dir /tmp/custom-dir を指定して autopilot-launch.sh を起動する
# THEN Worker 起動コマンドに AUTOPILOT_DIR=/tmp/custom-dir が含まれている
@test "autopilotdir: --autopilot-dir 引数が tmux new-window コマンドに AUTOPILOT_DIR として伝搬される" {
  _run_launch 42 "$CUSTOM_AUTOPILOT_DIR"

  assert_success
  _tmux_cmd_contains "AUTOPILOT_DIR=${CUSTOM_AUTOPILOT_DIR}"
}

@test "autopilotdir: 異なるカスタムパス (/tmp/my-ap) が正しく伝搬される" {
  local alt_dir
  alt_dir="$(mktemp -d)"
  mkdir -p "$alt_dir/trace"
  cat > "$alt_dir/session.json" <<JSON
{"session_id": "alt-session", "started_at": "2026-04-10T00:00:00Z"}
JSON

  _run_launch 10 "$alt_dir"

  assert_success
  _tmux_cmd_contains "AUTOPILOT_DIR=${alt_dir}"

  rm -rf "$alt_dir"
}

@test "autopilotdir: AUTOPILOT_DIR が env ... cld 形式で tmux new-window に渡される" {
  _run_launch 42 "$CUSTOM_AUTOPILOT_DIR"

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)

  # "env AUTOPILOT_DIR=..." パターンを確認
  echo "$tmux_cmd" | tr -d '\\' | grep -qE "env .*AUTOPILOT_DIR="
}

@test "autopilotdir: --autopilot-dir のパスが SANDBOX 内サブディレクトリでも正しく伝搬される" {
  local sub_dir="$SANDBOX/subdir/nested-ap"
  mkdir -p "$sub_dir/trace"
  cat > "$sub_dir/session.json" <<JSON
{"session_id": "sub-session", "started_at": "2026-04-10T00:00:00Z"}
JSON

  _run_launch 7 "$sub_dir"

  assert_success
  _tmux_cmd_contains "AUTOPILOT_DIR=${sub_dir}"
}

# ---------------------------------------------------------------------------
# Scenario 2: デフォルト AUTOPILOT_DIR が PROJECT_ROOT/.autopilot にフォールバックする
#
# NOTE: autopilotdir-state-split.bats の以下テストと重複しない:
#   - "AUTOPILOT_DIR override: default fallback uses PROJECT_ROOT/.autopilot"
#     (autopilot-init.sh のディレクトリ作成をテスト)
# こちらは autopilot-init.sh が生成する出力メッセージと
# AUTOPILOT_DIR 環境変数が設定されない状態での動作に焦点を当てる。
# ---------------------------------------------------------------------------

@test "autopilotdir: AUTOPILOT_DIR 未設定時 autopilot-init.sh が PROJECT_ROOT/.autopilot を作成しメッセージを出力する" {
  unset AUTOPILOT_DIR

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  # 初期化成功メッセージを含む
  assert_output --partial "OK"
  # $SANDBOX が PROJECT_ROOT として解決され .autopilot が作成される
  [ -d "$SANDBOX/.autopilot" ]
  [ -d "$SANDBOX/.autopilot/issues" ]
  [ -d "$SANDBOX/.autopilot/archive" ]
}

@test "autopilotdir: AUTOPILOT_DIR 未設定時 autopilot-init.sh の出力に issues パスが含まれる" {
  unset AUTOPILOT_DIR

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  # 出力に issues ディレクトリのパスが含まれる
  assert_output --partial "issues"
}

@test "autopilotdir: AUTOPILOT_DIR 未設定時 .autopilot 外のパスにはディレクトリが作成されない" {
  unset AUTOPILOT_DIR
  local alternate_dir="$SANDBOX/alternate-dir"

  run bash "$SANDBOX/scripts/autopilot-init.sh"

  assert_success
  # 代替パスには何も作成されない
  [ ! -d "$alternate_dir" ]
}

# ---------------------------------------------------------------------------
# Scenario 3: AUTOPILOT_DIR カスタム設定時に state ファイルが指定パスに書かれる
#
# NOTE: autopilotdir-state-split.bats の以下テストと重複しない:
#   - "state-write uses AUTOPILOT_DIR to update issue state"
#     (既存 JSON の更新をテスト)
#   - "Pilot and Worker share same state file via AUTOPILOT_DIR"
#     (Pilot/Worker 共有をテスト)
# こちらは state write --init による新規作成に焦点を当て、
# カスタム AUTOPILOT_DIR へ書かれ DEFAULT_AUTOPILOT_DIR には書かれないことを確認する。
# ---------------------------------------------------------------------------

@test "autopilotdir: state write --init がカスタム AUTOPILOT_DIR/issues/issue-N.json を作成する" {
  local custom_ap="$SANDBOX/custom-state-ap"
  export AUTOPILOT_DIR="$custom_ap"
  mkdir -p "$custom_ap/issues"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 55 --role worker --init

  assert_success
  [ -f "$custom_ap/issues/issue-55.json" ]
}

@test "autopilotdir: state write --init がデフォルト PROJECT_ROOT/.autopilot には書かない" {
  local custom_ap="$SANDBOX/custom-state-ap2"
  export AUTOPILOT_DIR="$custom_ap"
  mkdir -p "$custom_ap/issues"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 66 --role worker --init

  assert_success
  # カスタムパスに書かれる
  [ -f "$custom_ap/issues/issue-66.json" ]
  # デフォルトパス（$SANDBOX/.autopilot）には書かれない
  [ ! -f "$SANDBOX/.autopilot/issues/issue-66.json" ]
}

@test "autopilotdir: state write --set がカスタム AUTOPILOT_DIR のファイルを更新する" {
  local custom_ap="$SANDBOX/custom-state-ap3"
  export AUTOPILOT_DIR="$custom_ap"
  mkdir -p "$custom_ap/issues"

  # 初期 state を作成
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$custom_ap/issues/issue-77.json" <<JSON
{"issue": 77, "status": "running", "branch": "", "pr": null, "window": "", "started_at": "$now", "current_step": "", "retry_count": 0, "fix_instructions": null, "merged_at": null, "files_changed": [], "failure": null}
JSON

  run python3 -m twl.autopilot.state write \
    --type issue --issue 77 --role worker --set "status=merge-ready"

  assert_success

  # カスタムパスのファイルが更新されている
  local result
  result=$(jq -r '.status' "$custom_ap/issues/issue-77.json")
  [ "$result" = "merge-ready" ]

  # デフォルトパスには何も作成されていない
  [ ! -f "$SANDBOX/.autopilot/issues/issue-77.json" ]
}

@test "autopilotdir: 異なる issue 番号でも同じ AUTOPILOT_DIR に書かれる" {
  local custom_ap="$SANDBOX/multi-issue-ap"
  export AUTOPILOT_DIR="$custom_ap"
  mkdir -p "$custom_ap/issues"

  run python3 -m twl.autopilot.state write \
    --type issue --issue 10 --role worker --init
  assert_success

  run python3 -m twl.autopilot.state write \
    --type issue --issue 20 --role worker --init
  assert_success

  [ -f "$custom_ap/issues/issue-10.json" ]
  [ -f "$custom_ap/issues/issue-20.json" ]
  # デフォルトパスには書かれない
  [ ! -f "$SANDBOX/.autopilot/issues/issue-10.json" ]
  [ ! -f "$SANDBOX/.autopilot/issues/issue-20.json" ]
}

# ---------------------------------------------------------------------------
# Edge cases: --autopilot-dir バリデーション
# ---------------------------------------------------------------------------

@test "autopilotdir edge: --autopilot-dir 未指定時は exit 1 でエラー" {
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue 42 \
    --project-dir "$TEST_PROJECT_DIR"

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "--autopilot-dir"
}

@test "autopilotdir edge: --autopilot-dir に相対パスを指定した場合は exit 1 でエラー" {
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue 42 \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "relative/path"

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "絶対パス"
}

@test "autopilotdir edge: --autopilot-dir に パストラバーサル (/../) を含む場合は exit 1 でエラー" {
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue 42 \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "/tmp/valid/../traversal"

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "パストラバーサル"
}

@test "autopilotdir edge: --autopilot-dir に末尾 /.. を含む場合は exit 1 でエラー" {
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue 42 \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "/tmp/.."

  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "パストラバーサル"
}

@test "autopilotdir edge: AUTOPILOT_DIR を含む tmux コマンドに TWL_CHAIN_TRACE も含まれる" {
  _run_launch 42 "$CUSTOM_AUTOPILOT_DIR"

  assert_success
  _tmux_cmd_contains "TWL_CHAIN_TRACE="
}

@test "autopilotdir edge: AUTOPILOT_DIR に空白を含む場合でも tmux コマンドに正しく渡される" {
  local spaced_dir="$SANDBOX/dir with spaces"
  mkdir -p "$spaced_dir/trace"
  cat > "$spaced_dir/session.json" <<JSON
{"session_id": "space-session", "started_at": "2026-04-10T00:00:00Z"}
JSON

  _run_launch 42 "$spaced_dir"

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  # バックスラッシュエスケープを除去して "dir with spaces" が含まれることを確認
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "dir with spaces"
}

@test "autopilotdir edge: --autopilot-dir は --project-dir と異なるパスでも受け付ける" {
  local separate_ap="$SANDBOX/separate-ap"
  mkdir -p "$separate_ap/trace"
  cat > "$separate_ap/session.json" <<JSON
{"session_id": "sep-session", "started_at": "2026-04-10T00:00:00Z"}
JSON

  # project-dir と autopilot-dir が異なるパス
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue 42 \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "$separate_ap"

  assert_success
  _tmux_cmd_contains "AUTOPILOT_DIR=${separate_ap}"
  # project-dir のパスとは異なる
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | tr -d '\\' | grep -qv "AUTOPILOT_DIR=${TEST_PROJECT_DIR}"
}
