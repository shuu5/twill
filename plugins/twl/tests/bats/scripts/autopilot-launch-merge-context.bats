#!/usr/bin/env bats
# autopilot-launch-merge-context.bats
# Unit tests for autopilot-launch.sh: merge 禁止コンテキスト注入ロジック
#
# Spec: deltaspec/changes/issue-404/specs/invariant-c-enforcement/spec.md
#
# Coverage:
#   Scenario 3: Worker 起動時に merge 禁止コンテキストが注入される
#     WHEN autopilot-launch.sh が Worker（Claude Code）を起動する
#     THEN --append-system-prompt に「gh pr merge の直接実行は禁止。マージ権限は Pilot のみ（不変条件 C）」
#          というテキストが含まれている
#
# Edge cases:
#   - --context オプションで既存コンテキストがある場合でも merge 禁止が追加される
#   - merge 禁止テキストが --append-system-prompt として cld に渡される
#   - 全 Issue で merge 禁止が常時注入される
#
# 注記:
#   autopilot-launch.sh は printf '%q' でコンテキスト文字列をシェルエスケープして
#   tmux new-window に渡す。そのため tmux スタブが受け取る引数には
#   "gh\ pr\ merge" のようにバックスラッシュエスケープが含まれる。
#   アサーションは grep で部分一致を確認する（バックスラッシュの有無を問わない）。

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup: autopilot-launch.sh のコンテキスト構築ロジックを検証するための
#        test double スクリプトを用意する。
#
# テスト戦略:
#   autopilot-launch.sh は tmux new-window を呼ぶため、
#   tmux をスタブして cld の起動コマンドライン全体を TMUX_CMD_FILE に記録する。
#   printf '%q' によるエスケープを考慮し、grep で部分一致を確認する。
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # tmux スタブ: new-window の起動コマンドを記録する
  TMUX_CMD_FILE="$SANDBOX/tmux-new-window.txt"
  export TMUX_CMD_FILE
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  new-window)
    # コマンド全体を記録（エスケープ済み引数を含む）
    printf '%s\n' "\$*" >> "${TMUX_CMD_FILE}"
    exit 0 ;;
  set-option|set-hook|display-message|list-windows)
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # cld スタブ: 起動されたことを記録する（tmux スタブ内で実行されるため通常は不要）
  cat > "$STUB_BIN/cld" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_BIN/cld"

  # gh スタブ: project item-list + ラベルなし
  stub_command "gh" '
    case "$*" in
      *"project item-list"*)
        echo "{\"items\":[{\"id\":\"I_42\",\"content\":{\"number\":42,\"type\":\"Issue\"},\"status\":\"In Progress\"},{\"id\":\"I_1\",\"content\":{\"number\":1,\"type\":\"Issue\"},\"status\":\"In Progress\"},{\"id\":\"I_999\",\"content\":{\"number\":999,\"type\":\"Issue\"},\"status\":\"In Progress\"}]}" ;;
      *"repo view"*"--json owner"*)
        echo "shuu5" ;;
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

  # python3 スタブ: state write/read を無害化
  # worktree create は失敗させて WORKTREE_DIR が空のままにする
  cat > "$STUB_BIN/python3" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"worktree create"*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/python3"

  # .autopilot ディレクトリと最低限の session.json を用意
  mkdir -p "$SANDBOX/.autopilot/trace"
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-session-404", "started_at": "2026-04-10T00:00:00Z"}
JSON

  # テスト対象のプロジェクトディレクトリ（standard repo として扱う）
  mkdir -p "$SANDBOX/project/.git"
  TEST_PROJECT_DIR="$SANDBOX/project"
  export TEST_PROJECT_DIR
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario 3: Worker 起動時に merge 禁止コンテキストが注入される
# ---------------------------------------------------------------------------

# WHEN autopilot-launch.sh が Worker（Claude Code）を起動する
# THEN --append-system-prompt に「gh pr merge の直接実行は禁止。マージ権限は Pilot のみ（不変条件 C）」
#      というテキストが含まれている
@test "merge-context: Worker 起動時に --append-system-prompt が付与される" {
  _run_launch 42

  # tmux new-window が実行されたことを確認
  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | grep -q "\-\-append-system-prompt"
}

@test "merge-context: --append-system-prompt に 'gh pr merge' 禁止テキストが含まれる" {
  _run_launch 42

  assert_success
  _tmux_cmd_contains "gh pr merge"
}

@test "merge-context: --append-system-prompt に '不変条件 C' への言及が含まれる" {
  _run_launch 42

  assert_success
  _tmux_cmd_contains "不変条件 C"
}

@test "merge-context: --append-system-prompt にマージ権限は Pilot のみという内容が含まれる" {
  _run_launch 42

  assert_success
  _tmux_cmd_contains "Pilot"
}

# Edge case: --context オプションなし（デフォルト）でも merge 禁止が注入される
@test "merge-context: --context オプション未指定でも merge 禁止コンテキストが注入される" {
  _run_launch 42

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | grep -q "\-\-append-system-prompt"
  _tmux_cmd_contains "gh pr merge"
}

# Edge case: --context オプションありの場合、既存コンテキストに merge 禁止が追加される
@test "merge-context: --context オプション指定時も merge 禁止が追加される" {
  _run_launch 42 "--context カスタムコンテキスト"

  assert_success
  _tmux_cmd_contains "gh pr merge"
}

# Edge case: merge 禁止は全 Issue（Issue 番号に関係なく）に注入される
@test "merge-context: Issue 番号 1 でも merge 禁止コンテキストが注入される（全 Issue 常時注入）" {
  _run_launch 1

  assert_success
  _tmux_cmd_contains "gh pr merge"
}

@test "merge-context: Issue 番号 999 でも merge 禁止コンテキストが注入される（全 Issue 常時注入）" {
  _run_launch 999

  assert_success
  _tmux_cmd_contains "gh pr merge"
}

# ---------------------------------------------------------------------------
# Edge cases: CONTEXT 変数の構築ロジック検証
# ---------------------------------------------------------------------------

@test "merge-context: --append-system-prompt が cld コマンドの引数として渡される" {
  _run_launch 42

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)

  # tmux new-window の中に cld コマンドが含まれ、
  # --append-system-prompt が cld に渡されていること
  echo "$tmux_cmd" | grep -q "cld"
  echo "$tmux_cmd" | grep -q "\-\-append-system-prompt"
}

# merge 禁止コンテキスト注入は条件分岐なしの常時注入（ラベル検出に依存しない）
@test "merge-context: gh ラベル取得が失敗しても merge 禁止コンテキストは注入される（フォールバック安全性）" {
  # gh が全て失敗するスタブ
  stub_command "gh" 'exit 1'

  _run_launch 42

  # gh 失敗は Worker 起動を阻害しない
  # merge 禁止コンテキストは gh ラベル検出に依存しないため常時注入される
  _tmux_cmd_contains "gh pr merge"
}
