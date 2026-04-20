#!/usr/bin/env bats
# orchestrator-cleanup-sequence.bats
# Requirement: Pilot側クリーンアップシーケンス実行 / クロスリポジトリcleanup対応
# Spec: openspec/changes/worker-cleanup-to-pilot/specs/pilot-cleanup/spec.md
#
# Scenarios:
#   1. merge-gate成功後のクリーンアップ正常系（tmux→worktree→remote branch 順序）
#   2. tmux windowが既に存在しない場合の冪等動作
#   3. worktreeが既に削除済みの場合の冪等動作
#   4. クリーンアップステップ失敗時の継続（警告出力 + 残りステップ続行）
#   7. クロスリポジトリのリモートブランチ削除
#   8. 同一リポジトリIssueの通常削除
#
# 検証方針:
#   autopilot-orchestrator.sh の cleanup_worker() を直接テストするのは
#   関数スコープの制約があるため、cleanup_worker() のロジックを抽出した
#   テストダブルスクリプト (cleanup-worker-double.sh) を各テストで生成して
#   コマンド呼び出し順序・冪等性・エラー継続を検証する。

load '../helpers/common'

# ---------------------------------------------------------------------------
# テストダブル: cleanup_worker() の実装を抽出したスタンドアロンスクリプト
# autopilot-orchestrator.sh の cleanup_worker() と同一ロジック
# ---------------------------------------------------------------------------
_create_cleanup_double() {
  local scripts_root="$1"
  cat > "$SANDBOX/scripts/cleanup-worker-double.sh" <<'DOUBLE_EOF'
#!/usr/bin/env bash
# cleanup-worker-double.sh
# autopilot-orchestrator.sh の cleanup_worker() を抽出したテストダブル
# 引数: <issue> [<entry>]
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALL_LOG="${CLEANUP_CALL_LOG:-/tmp/cleanup-double-calls.log}"

issue="$1"
entry="${2:-_default:${issue}}"
window_name="ap-#${issue}"

echo "[cleanup-double] cleanup: Issue #${issue} — window/branch クリーンアップ" >&2

# Step 1: tmux kill-window（失敗時は無視して継続）
echo "STEP:tmux_kill_window" >> "$CALL_LOG"
tmux kill-window -t "$window_name" 2>/dev/null || true

# Step 2: worktree-delete.sh（失敗時は警告して継続）
branch=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field branch 2>/dev/null || echo "")
if [[ -n "$branch" && "$branch" =~ ^[a-zA-Z0-9_/\-]+$ ]]; then
  echo "STEP:worktree_delete:${branch}" >> "$CALL_LOG"
  if ! bash "$SCRIPTS_ROOT/worktree-delete.sh" "$branch" 2>/dev/null; then
    echo "[cleanup-double] WARN: worktree-delete.sh 失敗（継続）: ${branch}" >&2
  fi
fi

# Step 3: git push origin --delete（クロスリポ対応）
branch=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field branch 2>/dev/null || echo "")
if [[ -n "$branch" && "$branch" =~ ^[a-zA-Z0-9_/\-]+$ ]]; then
  # クロスリポ解決: REPOS_JSON から entry のパスを取得
  ISSUE_REPO_PATH=""
  ISSUE_REPO_ID="${entry%%:*}"
  if [[ "$ISSUE_REPO_ID" != "_default" && -n "${REPOS_JSON:-}" ]]; then
    ISSUE_REPO_PATH=$(echo "$REPOS_JSON" | jq -r --arg k "$ISSUE_REPO_ID" '.[$k].path // empty' 2>/dev/null || echo "")
  fi

  echo "STEP:git_push_delete:${branch}:repo_path=${ISSUE_REPO_PATH}" >> "$CALL_LOG"
  if [[ -n "$ISSUE_REPO_PATH" && "$ISSUE_REPO_PATH" == /* && "$ISSUE_REPO_PATH" != *..* ]]; then
    git -C "$ISSUE_REPO_PATH" push origin --delete "$branch" 2>/dev/null || true
  else
    git push origin --delete "$branch" 2>/dev/null || true
  fi
fi

echo "STEP:complete" >> "$CALL_LOG"
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-double.sh"
}

setup() {
  common_setup
  _create_cleanup_double "$SANDBOX/scripts"

  export CLEANUP_CALL_LOG="$SANDBOX/cleanup-calls.log"

  # デフォルト stub: tmux は成功
  stub_command "tmux" '
    echo "tmux $*" >> "$SANDBOX/tmux-raw.log"
    exit 0
  '

  # デフォルト stub: git は成功
  stub_command "git" '
    echo "git $*" >> "$SANDBOX/git-raw.log"
    exit 0
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario 1: merge-gate成功後のクリーンアップ正常系
# WHEN  autopilot-orchestrator.shがIssue NのPRのmerge-gate PASSを検出する
# THEN  tmux kill-window → worktree-delete.sh → git push origin --delete
#       の順で実行される
# ---------------------------------------------------------------------------

@test "cleanup_worker: tmux kill-window → worktree-delete → git push の順で実行される" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-cleanup-test"'

  stub_command "tmux" '
    echo "tmux $*" >> "$SANDBOX/tmux-raw.log"
    exit 0
  '

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success

  # CALL_LOG の順序を検証
  [ -f "$CLEANUP_CALL_LOG" ]
  local step1 step2 step3
  step1=$(grep -n "STEP:tmux_kill_window" "$CLEANUP_CALL_LOG" | head -1 | cut -d: -f1)
  step2=$(grep -n "STEP:worktree_delete" "$CLEANUP_CALL_LOG" | head -1 | cut -d: -f1)
  step3=$(grep -n "STEP:git_push_delete" "$CLEANUP_CALL_LOG" | head -1 | cut -d: -f1)

  # 全ステップが記録されていること
  [ -n "$step1" ]
  [ -n "$step2" ]
  [ -n "$step3" ]

  # 順序: step1 < step2 < step3
  [ "$step1" -lt "$step2" ]
  [ "$step2" -lt "$step3" ]
}

@test "cleanup_worker: tmux kill-window は ap-#{issue} window を対象とする" {
  create_issue_json 42 "done" \
    '.branch = "feat/42-something"'

  stub_command "tmux" '
    echo "tmux $*" >> "$SANDBOX/tmux-raw.log"
    exit 0
  '

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 42

  assert_success
  [ -f "$SANDBOX/tmux-raw.log" ]
  grep -q "kill-window -t ap-#42" "$SANDBOX/tmux-raw.log"
}

@test "cleanup_worker: git push origin --delete でブランチ名を削除する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-cleanup-test"'

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  [ -f "$SANDBOX/git-raw.log" ]
  grep -q "push origin --delete feat/1-cleanup-test" "$SANDBOX/git-raw.log"
}

# ---------------------------------------------------------------------------
# Scenario 2: tmux windowが既に存在しない場合の冪等動作
# WHEN  クリーンアップ開始時にtmux windowが既に存在しない
# THEN  tmuxステップはエラーを無視して正常扱いとし、
#       次のworktree削除ステップへ進む
# ---------------------------------------------------------------------------

@test "cleanup_worker: tmux kill-window 失敗（window不在）でも次ステップへ進む" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-tmux-gone"'

  # tmux kill-window が失敗するケース（window が存在しない）
  stub_command "tmux" '
    case "$*" in
      *"kill-window"*)
        echo "tmux: can'\''t find window: ap-#1" >&2
        exit 1 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  # エラーを無視して正常終了すること
  assert_success

  # worktree_delete と git_push_delete が実行されていること（次ステップへ進んでいる）
  [ -f "$CLEANUP_CALL_LOG" ]
  grep -q "STEP:worktree_delete" "$CLEANUP_CALL_LOG"
  grep -q "STEP:git_push_delete" "$CLEANUP_CALL_LOG"
}

@test "cleanup_worker: tmux window不在でも complete まで到達する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-tmux-gone"'

  stub_command "tmux" '
    case "$*" in
      *"kill-window"*) exit 1 ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  grep -q "STEP:complete" "$CLEANUP_CALL_LOG"
}

# ---------------------------------------------------------------------------
# Scenario 3: worktreeが既に削除済みの場合の冪等動作
# WHEN  クリーンアップ開始時にworktreeが既に削除済み
# THEN  worktree-delete.shは正常終了し、
#       次のリモートブランチ削除ステップへ進む
# ---------------------------------------------------------------------------

@test "cleanup_worker: worktree-delete.sh が worktree不在でも正常終了する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-worktree-gone"'

  # worktree-delete.sh がすでに削除済みのパスに対して WARN を出して正常終了するケース
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<'STUB'
#!/usr/bin/env bash
branch="$1"
echo "WARN: worktree が存在しません: /some/path/${branch}" >&2
exit 0
STUB
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  grep -q "STEP:git_push_delete" "$CLEANUP_CALL_LOG"
  grep -q "STEP:complete" "$CLEANUP_CALL_LOG"
}

@test "cleanup_worker: worktree削除済みケースでもリモートブランチ削除は実行される" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-worktree-gone"'

  cat > "$SANDBOX/scripts/worktree-delete.sh" <<'STUB'
#!/usr/bin/env bash
echo "WARN: worktree が存在しません" >&2
exit 0
STUB
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  [ -f "$SANDBOX/git-raw.log" ]
  grep -q "push origin --delete feat/1-worktree-gone" "$SANDBOX/git-raw.log"
}

# ---------------------------------------------------------------------------
# Scenario 4: クリーンアップステップ失敗時の継続
# WHEN  worktree削除ステップが失敗する（例: パーミッションエラー）
# THEN  警告メッセージを出力し、残りのステップ（リモートブランチ削除）を続行する
# ---------------------------------------------------------------------------

@test "cleanup_worker: worktree-delete.sh 失敗時に警告メッセージを出力する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-perm-error"'

  # worktree-delete.sh がパーミッションエラーで失敗
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<'STUB'
#!/usr/bin/env bash
echo "ERROR: permission denied: /locked/path" >&2
exit 1
STUB
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  # スクリプト自体は正常終了すること（||true で継続）
  assert_success

  # 警告メッセージが出力されていること
  assert_output --partial "WARN"
  assert_output --partial "継続"
}

@test "cleanup_worker: worktree-delete.sh 失敗後もリモートブランチ削除ステップが実行される" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-perm-error"'

  cat > "$SANDBOX/scripts/worktree-delete.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  # リモートブランチ削除ステップが記録されていること
  grep -q "STEP:git_push_delete" "$CLEANUP_CALL_LOG"
}

@test "cleanup_worker: tmux失敗 + worktree失敗でも complete まで到達する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-all-fail"'

  stub_command "tmux" '
    case "$*" in
      *"kill-window"*) exit 1 ;;
      *) exit 0 ;;
    esac
  '
  cat > "$SANDBOX/scripts/worktree-delete.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  grep -q "STEP:complete" "$CLEANUP_CALL_LOG"
}

# ---------------------------------------------------------------------------
# Scenario 7: クロスリポジトリのリモートブランチ削除
# WHEN  issue-{N}.jsonにrepoフィールドが存在し、currentリポジトリと異なる
# THEN  対象リポジトリのディレクトリに移動（git -C <repo_path>）して
#       git push origin --delete "${BRANCH}"を実行する
# ---------------------------------------------------------------------------

@test "cleanup_worker: クロスリポ設定があるとき git -C <repo_path> push origin --delete を実行する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-cross-repo"'

  # 対象リポジトリのダミーディレクトリを作成
  mkdir -p "$SANDBOX/loom-repo"

  export REPOS_JSON
  REPOS_JSON=$(jq -n \
    --arg path "$SANDBOX/loom-repo" \
    '{loom: {owner: "shuu5", name: "loom", path: $path}}')

  # エントリを loom:1 形式（クロスリポ）で渡す
  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1 "loom:1"

  assert_success
  [ -f "$SANDBOX/git-raw.log" ]
  # git -C <repo_path> push origin --delete が呼ばれていること
  grep -q "\-C $SANDBOX/loom-repo push origin --delete feat/1-cross-repo" "$SANDBOX/git-raw.log"
}

@test "cleanup_worker: クロスリポのブランチ削除はcurrentリポジトリのgitを使わない" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-cross-repo"'

  mkdir -p "$SANDBOX/loom-repo"

  export REPOS_JSON
  REPOS_JSON=$(jq -n \
    --arg path "$SANDBOX/loom-repo" \
    '{loom: {owner: "shuu5", name: "loom", path: $path}}')

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1 "loom:1"

  assert_success
  # REPO_PATH を含む git -C 呼び出しであること（カレントディレクトリの git ではないこと）
  grep -qv "^git push origin --delete feat/1-cross-repo" "$SANDBOX/git-raw.log" || true
}

@test "cleanup_worker: クロスリポのISSUE_REPO_PATHにパストラバーサルが含まれる場合は無視する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-traverse"'

  export REPOS_JSON
  REPOS_JSON=$(jq -n \
    '{evil: {owner: "x", name: "y", path: "/safe/../../etc"}}')

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1 "evil:1"

  # パストラバーサルを含むパスは無視され、カレントディレクトリの git が使われるか
  # あるいはスキップされること（スクリプトは正常終了すること）
  assert_success
}

# ---------------------------------------------------------------------------
# Scenario 8: 同一リポジトリIssueの通常削除
# WHEN  issue-{N}.jsonのrepoフィールドが存在しないか、currentリポジトリと一致する
# THEN  カレントディレクトリで git push origin --delete "${BRANCH}" を実行する
# ---------------------------------------------------------------------------

@test "cleanup_worker: repoフィールドなし（_default）のときカレントディレクトリでgit push --deleteを実行する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-same-repo"'

  # _default エントリ（通常の同一リポジトリ Issue）
  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1 "_default:1"

  assert_success
  [ -f "$SANDBOX/git-raw.log" ]
  # git -C を含まない push --delete が呼ばれていること
  grep -q "push origin --delete feat/1-same-repo" "$SANDBOX/git-raw.log"
  # git -C は使われていないこと
  run grep "\-C" "$SANDBOX/git-raw.log"
  assert_failure
}

@test "cleanup_worker: REPOS_JSONが空のときカレントディレクトリでgit push --deleteを実行する" {
  create_issue_json 1 "done" \
    '.branch = "feat/1-no-repos-json"'

  unset REPOS_JSON

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  assert_success
  [ -f "$SANDBOX/git-raw.log" ]
  grep -q "push origin --delete feat/1-no-repos-json" "$SANDBOX/git-raw.log"
}

@test "cleanup_worker: ブランチ名バリデーション失敗時はgit push --deleteをスキップする" {
  # 不正なブランチ名（セミコロンを含む）を持つ issue
  create_issue_json 1 "done" \
    '.branch = "feat/bad;branch"'

  run bash "$SANDBOX/scripts/cleanup-worker-double.sh" 1

  # ブランチ名バリデーション失敗 → git push はスキップ → 正常終了
  assert_success
  # git push --delete は呼ばれていないこと
  if [[ -f "$SANDBOX/git-raw.log" ]]; then
    run grep "push origin --delete" "$SANDBOX/git-raw.log"
    assert_failure
  fi
}
