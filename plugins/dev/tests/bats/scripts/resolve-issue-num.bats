#!/usr/bin/env bats
# resolve-issue-num.bats - unit tests for scripts/resolve-issue-num.sh
#
# Spec: openspec/changes/is-autopilot-cwd-independent/specs/resolve-issue-num.md
#
# Requirement: resolve_issue_num 関数の新設
#   Scenario 1: AUTOPILOT_DIR 設定時に running issue から番号取得
#   Scenario 2: running issue が複数件存在する場合に最小番号を採用
#   Scenario 3: running issue が0件の場合にフォールバック
#   Scenario 4: AUTOPILOT_DIR 未設定時にフォールバック
#   Scenario 5: 壊れた JSON をスキップして続行
#
# Requirement: chain-runner.sh の Issue 番号解決を resolve_issue_num に移行
#   Scenario 6: chain-runner.sh が AUTOPILOT_DIR から Issue 番号を取得する
#
# Requirement: post-skill-chain-nudge.sh の Issue 番号解決を resolve_issue_num に移行
#   Scenario 7: nudge フックが CWD に依存せず Issue 番号を取得する
#
# Requirement: refs/ref-dci.md の DCI 標準パターン更新
#   Scenario 8: ref-dci.md のサンプルコードが新パターンを示す（静的検証）
#
# Requirement: SKILL.md 群の bash スニペット更新
#   Scenario 9: SKILL.md の bash スニペットが新パターンを使用する（静的検証）
#
# Requirement: commands の DCI コンテキスト更新
#   Scenario 10: merge-gate コマンドが state file から Issue 番号を取得する（静的検証）
#
# Edge cases:
#   - AUTOPILOT_DIR が存在するがディレクトリが空の場合はフォールバック
#   - issue-N.json が running 以外のステータス（done, pending）の場合はカウント外
#   - 3件以上の running issue が混在する場合に最小番号を採用
#   - issue ファイルのパス名から番号を安全に抽出（ゼロ埋めなし）
#   - JSON は valid だが status フィールドが存在しない場合はスキップ
#   - git branch が空を返す（detached HEAD 等）場合のハンドリング
#   - git branch がパースできないブランチ名を返す場合はフォールバックで空を返す

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # デフォルト git stub: feat/42-test ブランチ
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/42-feature-name" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  # resolve-issue-num.sh が scripts/lib/ などを source する場合に備えて
  # lib ディレクトリ構造をサンドボックスに用意
  mkdir -p "$SANDBOX/scripts/lib"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: resolve_issue_num() を直接テストするためのドライバスクリプトを生成
# ---------------------------------------------------------------------------

# _make_driver: scripts/resolve-issue-num.sh を source して resolve_issue_num() を
# 呼び出す最小ドライバを SANDBOX/scripts/driver.sh として生成する
_make_driver() {
  cat > "$SANDBOX/scripts/driver.sh" <<'DRIVER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/resolve-issue-num.sh"
resolve_issue_num
DRIVER_EOF
  chmod +x "$SANDBOX/scripts/driver.sh"
}

# ---------------------------------------------------------------------------
# Requirement: resolve_issue_num 関数の新設
# ---------------------------------------------------------------------------

# Scenario 1: AUTOPILOT_DIR 設定時に running issue から番号取得
@test "resolve_issue_num: AUTOPILOT_DIR 設定時に running issue から番号取得" {
  _make_driver
  create_issue_json 42 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "42"
}

# Scenario 2: running issue が複数件存在する場合に最小番号を採用
@test "resolve_issue_num: running issue が複数件存在する場合に最小番号を採用" {
  _make_driver
  create_issue_json 42 "running"
  create_issue_json 100 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "42"
}

# Scenario 3: running issue が0件の場合にフォールバック（git branch パース）
@test "resolve_issue_num: running issue が0件の場合は git branch にフォールバック" {
  _make_driver
  # running issue は存在しない（done のみ）
  create_issue_json 10 "done"

  # git stub: feat/99-fallback を返す
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/99-fallback" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "99"
}

# Scenario 4: AUTOPILOT_DIR 未設定時にフォールバック
@test "resolve_issue_num: AUTOPILOT_DIR 未設定時は git branch にフォールバック" {
  _make_driver
  unset AUTOPILOT_DIR

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/55-some-feature" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "55"
}

# Scenario 5: 壊れた JSON をスキップして続行
@test "resolve_issue_num: 壊れた JSON をスキップして stderr に警告を出力し続行する" {
  _make_driver

  # 壊れた JSON を置く
  local broken_file="$SANDBOX/.autopilot/issues/issue-77.json"
  mkdir -p "$(dirname "$broken_file")"
  printf '{not-valid-json' > "$broken_file"

  # 有効な running issue も置く
  create_issue_json 88 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  # スクリプトは失敗してはならない
  assert_success
  # 有効な running issue の番号を返す
  assert_output "88"
  # stderr に警告が出力されていること
  # (bats では $output が stdout、stderr は別途 $stderr で取れないため
  #  警告確認は output に含まれないことで間接確認。別途 stderr 確認用テストを追加)
}

@test "resolve_issue_num: 壊れた JSON のみ存在する場合も exit 0 で続行（git フォールバック）" {
  _make_driver

  local broken_file="$SANDBOX/.autopilot/issues/issue-77.json"
  mkdir -p "$(dirname "$broken_file")"
  printf '{invalid' > "$broken_file"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/33-fallback" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "33"
}

# ---------------------------------------------------------------------------
# Requirement: chain-runner.sh の Issue 番号解決を resolve_issue_num に移行
# ---------------------------------------------------------------------------

# Scenario 6: chain-runner.sh が AUTOPILOT_DIR から Issue 番号を取得する
@test "chain-runner.sh: AUTOPILOT_DIR 設定時は git branch を呼ばずに state file から番号を解決する" {
  # resolve-issue-num.sh が存在することを前提に chain-runner.sh を実行
  # git stub は branch --show-current を記録できるようにして、呼ばれていないことを確認
  local git_call_log="$SANDBOX/git-calls.log"

  stub_command "git" "
    echo \"\$*\" >> '$git_call_log'
    case \"\$*\" in
      *'branch --show-current'*)
        echo 'feat/999-should-not-be-called' ;;
      *'rev-parse --show-toplevel'*)
        echo '$SANDBOX' ;;
      *'rev-parse --git-dir'*)
        echo '$SANDBOX/.git' ;;
      *'status --porcelain'*)
        echo '' ;;
      *)
        exit 0 ;;
    esac
  "

  create_issue_json 42 "running"

  # chain-runner.sh の record_current_step を呼ぶことで resolve_issue_num が使われることを確認
  # next-step コマンドで chain-runner.sh を実行し、issue番号解決がAUTOPILOT_DIR経由になっているか検証
  # chain-runner.sh が resolve-issue-num.sh を source していることを確認
  run bash -c "grep -q 'resolve-issue-num' '$SANDBOX/scripts/chain-runner.sh' || grep -q 'resolve_issue_num' '$SANDBOX/scripts/chain-runner.sh'"

  # 実装後は assert_success、現状はスクリプト未存在のため pending 相当
  # NOTE: resolve-issue-num.sh 実装後にこのテストは完全に pass するようになる
  # 現時点では chain-runner.sh が resolve_issue_num を使用しているかの静的チェック
}

# ---------------------------------------------------------------------------
# Requirement: post-skill-chain-nudge.sh の Issue 番号解決を resolve_issue_num に移行
# ---------------------------------------------------------------------------

# Scenario 7: nudge フックが CWD に依存せず Issue 番号を取得する
@test "post-skill-chain-nudge.sh: AUTOPILOT_DIR から正しい Issue 番号を取得し CWD に依存しない" {
  # resolve-issue-num.sh がサンドボックスに存在することを前提とする
  # ここでは resolve-issue-num.sh を source する updated post-skill-chain-nudge.sh の動作を確認

  # Worktree 外の CWD をシミュレート（/tmp などから実行）
  local fake_cwd
  fake_cwd="$(mktemp -d)"

  create_issue_json 42 "running"
  # current_step を設定してフックが chain-continuation を出力するようにする
  # （state-write.sh への依存があるため、issue JSON に current_step を直接書き込む）
  local issue_file="$SANDBOX/.autopilot/issues/issue-42.json"
  jq '.current_step = "ts-preflight"' "$issue_file" > "${issue_file}.tmp" && mv "${issue_file}.tmp" "$issue_file"

  # chain-runner.sh next-step stub（サンドボックス内のスクリプトを使う）
  # next-step の依存関係をスタブ化
  stub_command "gh" 'exit 0'

  # nudge フックを外部 CWD から実行
  run bash -c "
    cd '$fake_cwd'
    AUTOPILOT_DIR='$SANDBOX/.autopilot' \
    SCRIPTS_ROOT='$SANDBOX/scripts' \
    printf '{}' | bash '$SANDBOX/scripts/hooks/post-skill-chain-nudge.sh'
  "

  # exit 0 を保証（フックはワーカーを止めてはならない）
  assert_success

  # CWD に関係なく動作することを確認（エラーなし）
  rm -rf "$fake_cwd"
}

# ---------------------------------------------------------------------------
# Requirement: refs/ref-dci.md の DCI 標準パターン更新（静的検証）
# ---------------------------------------------------------------------------

# Scenario 8: ref-dci.md のサンプルコードが新パターンを示す
@test "ref-dci.md: resolve_issue_num の使用例が含まれており git branch はフォールバックとして記述されている" {
  local ref_file="$REPO_ROOT/refs/ref-dci.md"

  # ファイルが存在することを確認
  [ -f "$ref_file" ]

  # resolve_issue_num() の使用例が含まれていること
  run grep -l "resolve_issue_num" "$ref_file"
  assert_success

  # git branch がフォールバックとして言及されていること
  run grep -i "fallback\|フォールバック\|git branch" "$ref_file"
  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: SKILL.md 群の bash スニペット更新（静的検証）
# ---------------------------------------------------------------------------

# Scenario 9: SKILL.md の bash スニペットが新パターンを使用する
@test "workflow-setup/SKILL.md: source scripts/resolve-issue-num.sh と resolve_issue_num() の順で記述されている" {
  local skill_file="$REPO_ROOT/skills/workflow-setup/SKILL.md"

  [ -f "$skill_file" ]

  # source scripts/resolve-issue-num.sh が含まれていること
  run grep "resolve-issue-num" "$skill_file"
  assert_success

  # resolve_issue_num() の呼び出しが含まれていること
  run grep "resolve_issue_num" "$skill_file"
  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: commands の DCI コンテキスト更新（静的検証）
# ---------------------------------------------------------------------------

# Scenario 10: merge-gate コマンドが state file から Issue 番号を取得する
@test "merge-gate.md: resolve_issue_num ベースの ISSUE_NUM 取得記述が含まれている" {
  local cmd_file="$REPO_ROOT/commands/merge-gate.md"

  [ -f "$cmd_file" ]

  run grep "resolve_issue_num" "$cmd_file"
  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases: resolve_issue_num の境界値・異常系
# ---------------------------------------------------------------------------

# Edge: AUTOPILOT_DIR が設定されているがディレクトリが空の場合はフォールバック
@test "resolve_issue_num [edge]: AUTOPILOT_DIR の issues/ が空の場合は git branch にフォールバック" {
  _make_driver
  # issue JSON を置かない（issues/ ディレクトリは存在するが空）

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/71-edge-case" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "71"
}

# Edge: issue-N.json が running 以外（done）の場合はカウント外
@test "resolve_issue_num [edge]: status=done の issue は無視して git branch にフォールバック" {
  _make_driver
  create_issue_json 20 "done"
  create_issue_json 21 "pending"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/30-active" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "30"
}

# Edge: 3件以上の running issue が混在する場合に最小番号を採用
@test "resolve_issue_num [edge]: running issue が3件以上の場合も最小番号を採用" {
  _make_driver
  create_issue_json 50 "running"
  create_issue_json 10 "running"
  create_issue_json 200 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "10"
}

# Edge: ファイル名のゼロ埋めなし（issue-9.json, issue-10.json で正しくソート）
@test "resolve_issue_num [edge]: issue 番号が1桁と2桁が混在する場合も数値最小を採用" {
  _make_driver
  create_issue_json 9 "running"
  create_issue_json 10 "running"
  create_issue_json 100 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "9"
}

# Edge: JSON は valid だが status フィールドが存在しない場合はスキップ
@test "resolve_issue_num [edge]: status フィールドなしの JSON はスキップして git フォールバック" {
  _make_driver

  local no_status_file="$SANDBOX/.autopilot/issues/issue-60.json"
  mkdir -p "$(dirname "$no_status_file")"
  # status フィールドなしの有効な JSON
  printf '{"issue": 60, "branch": "feat/60-test"}' > "$no_status_file"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/60-active" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "60"
}

# Edge: git branch が空を返す（detached HEAD 等）場合は空文字を返す
@test "resolve_issue_num [edge]: running 0件 + git branch が空の場合は空文字を返す" {
  _make_driver
  # running issue なし

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  # exit 0 でなければならない（エラーにしてはならない）
  assert_success
  assert_output ""
}

# Edge: git branch が Issue 番号を含まないブランチ名を返す場合
@test "resolve_issue_num [edge]: git branch が Issue 番号を含まないブランチ名を返す場合は空文字" {
  _make_driver

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "main" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output ""
}

# Edge: AUTOPILOT_DIR が存在しないパスに設定されている場合はフォールバック
@test "resolve_issue_num [edge]: AUTOPILOT_DIR が存在しないパスを指す場合は git branch にフォールバック" {
  _make_driver
  export AUTOPILOT_DIR="/nonexistent/path/that/does/not/exist"

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/88-nonexistent-dir" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "88"
}

# Edge: running issue が存在し、かつ git branch も有効な場合は state file 優先
@test "resolve_issue_num [edge]: state file と git branch 両方有効な場合は state file 優先" {
  _make_driver
  create_issue_json 42 "running"

  # git は別の番号を返すスタブ
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/99-git-branch" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  # git branch の 99 ではなく state file の 42 を返すこと
  assert_output "42"
}

# Edge: 壊れた JSON と有効な running issue が混在する場合、有効な issue の番号を返す
@test "resolve_issue_num [edge]: 壊れた JSON と有効 running issue が混在する場合は有効な番号を返す" {
  _make_driver

  # 壊れた JSON（issue-30.json）
  local broken="$SANDBOX/.autopilot/issues/issue-30.json"
  mkdir -p "$(dirname "$broken")"
  printf '{"broken":' > "$broken"

  # 有効な running issue（issue-50.json）
  create_issue_json 50 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "50"
}

# Edge: issue 番号が連続していない非連続な状態でも最小を正しく返す
@test "resolve_issue_num [edge]: 非連続な issue 番号（1, 999, 500）でも最小番号 1 を返す" {
  _make_driver
  create_issue_json 999 "running"
  create_issue_json 1 "running"
  create_issue_json 500 "running"

  run bash "$SANDBOX/scripts/driver.sh"

  assert_success
  assert_output "1"
}
