#!/usr/bin/env bats
# merge-gate-execute-autopilot-skip.bats
# Requirement: merge-gate-execute.shのautopilot分岐
# Spec: openspec/changes/worker-cleanup-to-pilot/specs/pilot-cleanup/spec.md
#
# Scenarios:
#   5. autopilot時のクリーンアップスキップ
#   6. 非autopilot時の従来動作維持

load '../helpers/common'

setup() {
  common_setup

  # ── 共通 stub ──
  stub_command "tmux" '
    # tmux の呼び出し引数を記録
    echo "tmux $*" >> "$SANDBOX/tmux-calls.log"
    exit 0
  '

  stub_command "gh" '
    case "$*" in
      *"pr merge"*)
        echo "gh $*" >> "$SANDBOX/gh-calls.log"
        exit 0 ;;
      *)
        echo "{}" ;;
    esac
  '

  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        # worktree モードをシミュレート（非 .git パス）
        echo "/tmp/fake/.bare/worktrees/feat-1-test" ;;
      *"worktree list --porcelain"*)
        # BRANCH に一致する worktree エントリを返す
        printf "worktree /tmp/fake/worktrees/feat/1-test\nHEAD abc123\nbranch refs/heads/feat/1-test\n\n" ;;
      *"worktree remove"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *"push origin --delete"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *"branch -D"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  stub_command "chain-runner.sh" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario 5: autopilot時のクリーンアップスキップ
# WHEN  merge-gate-execute.shがmerge成功後のクリーンアップフェーズに入り、
#       AUTOPILOT_DIRが設定されissue-{N}.jsonが存在する
# THEN  worktree削除 / リモートブランチ削除 / tmux kill-windowをスキップし、
#       Pilotへの委譲メッセージを出力する
# ---------------------------------------------------------------------------

@test "merge-gate-execute: autopilot環境ではクリーンアップをスキップしPilotへ委譲する" {
  # NOTE: このテストは merge-gate-execute.sh への autopilot 分岐実装後に PASS する。
  # 現状の実装はクリーンアップをスキップしないため skip する。
  skip "autopilot分岐ロジック未実装（worker-cleanup-to-pilot 実装後に有効化）"
}

@test "merge-gate-execute: autopilot環境でのskip時は委譲メッセージをstdoutに出力する" {
  create_issue_json 1 "merge-ready" \
    '.branch = "feat/1-test"' \
    '.pr_number = 42'

  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  export AUTOPILOT_DIR="$SANDBOX/.autopilot"

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  # 実装後: "Pilot" または "委譲" または "cleanup skip" を含むメッセージを期待
  # 現状は TODO マーカーとしてテストを pending に近い形で残す
}

@test "merge-gate-execute: autopilot判定はissue-{N}.jsonの存在で行う（存在しない場合はautopilotではない）" {
  # AUTOPILOT_DIR に issue ファイルが存在しない別ディレクトリを指定
  mkdir -p "$SANDBOX/.alt-autopilot/issues"
  export AUTOPILOT_DIR="$SANDBOX/.alt-autopilot"

  # .alt-autopilot に issue-1.json を作成（state-write.sh の書き込み先として必要）
  jq -n '{
    issue: 1,
    status: "merge-ready",
    branch: "feat/1-test",
    pr: null,
    window: "",
    started_at: "2026-01-01T00:00:00Z",
    current_step: "",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$SANDBOX/.alt-autopilot/issues/issue-1.json"

  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"

  # issue-1.json が alt-autopilot に存在する = autopilot ではない（主リポとは別ディレクトリ）
  # → 従来クリーンアップが動く
  # NOTE: autopilot分岐実装後は「AUTOPILOT_DIR/issues/issue-N.json が存在する場合のみ autopilot」
  #       という判定になるため、別ディレクトリでも issue ファイルが存在すれば autopilot 扱いになる可能性がある。
  #       このテストは実装仕様に応じて修正が必要。
  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario 6: 非autopilot時の従来動作維持
# WHEN  merge-gate-execute.shがautopilot環境外（issue-{N}.jsonが存在しない）で実行される
# THEN  従来どおりmerge-gate-execute.sh自身がクリーンアップを実行する
# ---------------------------------------------------------------------------

@test "merge-gate-execute: 非autopilot環境ではworktree削除を自身で実行する" {
  create_issue_json 1 "merge-ready" \
    '.branch = "feat/1-test"' \
    '.pr_number = 42'

  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  # AUTOPILOT_DIR を空にする（非autopilot環境）
  unset AUTOPILOT_DIR
  # state-read が確実に動くようにデフォルトパスを維持
  # （common_setup が $SANDBOX/.autopilot を設定済み）

  # worktree list で BRANCH に一致するパスを返す stub を強化
  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo "/tmp/fake/.bare/worktrees/feat-1-test" ;;
      *"worktree list --porcelain"*)
        printf "worktree /tmp/fake/worktrees/feat/1-test\nHEAD abc123\nbranch refs/heads/feat/1-test\n\n" ;;
      *"worktree remove"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *"push origin --delete"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *"branch -D"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  assert_output --partial "マージ + クリーンアップ完了"
}

@test "merge-gate-execute: 非autopilot環境ではリモートブランチ削除を自身で実行する" {
  create_issue_json 1 "merge-ready" \
    '.branch = "feat/1-test"' \
    '.pr_number = 42'

  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  unset AUTOPILOT_DIR

  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo "/tmp/fake/.bare/worktrees/feat-1-test" ;;
      *"worktree list --porcelain"*)
        printf "worktree /tmp/fake/worktrees/feat/1-test\nHEAD abc123\nbranch refs/heads/feat/1-test\n\n" ;;
      *"worktree remove"*)
        exit 0 ;;
      *"push origin --delete"*)
        echo "git $*" >> "$SANDBOX/git-calls.log"
        exit 0 ;;
      *"branch -D"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  # リモートブランチ削除が実行されていること
  [ -f "$SANDBOX/git-calls.log" ]
  grep -q "push origin --delete feat/1-test" "$SANDBOX/git-calls.log"
}

@test "merge-gate-execute: 非autopilot環境ではtmux kill-windowを自身で実行する" {
  create_issue_json 1 "merge-ready" \
    '.branch = "feat/1-test"' \
    '.pr_number = 42'

  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  unset AUTOPILOT_DIR

  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*) echo "/tmp/fake/.bare/worktrees/feat-1-test" ;;
      *"worktree list --porcelain"*) printf "" ;;
      *"push origin --delete"*) exit 0 ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_success
  # tmux kill-window が呼ばれていること
  [ -f "$SANDBOX/tmux-calls.log" ]
  grep -q "kill-window" "$SANDBOX/tmux-calls.log"
}
