#!/usr/bin/env bats
# issue-create-refined.bats — RED-phase tests for Issue #1469
#
# Issue #1469: `gh issue create` で Bug Issue 起票後 Project Board Status=Todo のまま。
# autopilot orchestrator の Refined 必須 gate で reject される。
#
# AC coverage:
#   AC1 - 統合 script (Approach A) を `scripts/issue-create-refined.sh` に実装、bats test 追加
#   AC2 - 既存 `gh issue create` 呼び出しを段階的に新 script に migrate (co-issue / observer 起票 path)
#   AC3 - GitHub Actions (Approach C) で fallback 自動化 (tech-debt label 検出 → Refined 遷移)
#   AC4 - Wave 54+ で bug Issue 起票 → autopilot spawn が手動介入なしで通過する（smoke）

load '../helpers/common'

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*) echo ".git" ;;
      *"branch --show-current"*) echo "feat/1469-test" ;;
      *) exit 0 ;;
    esac
  '

  stub_command "gh" 'exit 0'
  stub_command "sleep" 'exit 0'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: 統合 script `scripts/issue-create-refined.sh` が存在し実行可能である
# ---------------------------------------------------------------------------

@test "ac1: issue-create-refined.sh が scripts/ に存在し実行可能である" {
  # AC: 統合 script (Approach A) を `scripts/issue-create-refined.sh` に実装、bats test 追加
  # RED: 実装前は fail する（ファイル未作成）
  local script="$REPO_ROOT/scripts/issue-create-refined.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }
  [[ -x "$script" ]] || {
    echo "FAIL: $script が実行可能でない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC1: issue-create-refined.sh を実行すると gh issue create かつ board-status-update Refined を呼ぶ
# ---------------------------------------------------------------------------

@test "ac1: issue-create-refined.sh が gh issue create と board-status-update Refined を実行する" {
  # AC: 統合 script は gh issue create を呼び出した後 Status=Refined に設定する
  # RED: 実装前は fail する

  local script="$SANDBOX/scripts/issue-create-refined.sh"
  if [[ ! -f "$script" ]]; then
    # ファイル未存在のため期待通り fail
    false
    return
  fi

  local call_log="$SANDBOX/gh_calls.log"
  stub_command "gh" "echo \"\$*\" >> '$call_log'; echo '1469'"

  stub_command "chain-runner.sh" "echo \"chain: \$*\" >> '$call_log'"

  run bash "$script" \
    --title "test bug" \
    --body "bug body" \
    --label "bug" \
    --repo "shuu5/twill"

  assert_success
  grep -q "issue create" "$call_log" || {
    echo "FAIL: gh issue create が呼ばれていない" >&2
    return 1
  }
  grep -q "Refined" "$call_log" || {
    echo "FAIL: board-status-update Refined が呼ばれていない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: co-issue-manual-fix-b.sh が issue-create-refined.sh を利用している
# ---------------------------------------------------------------------------

@test "ac2: co-issue-manual-fix-b.sh が issue-create-refined.sh を参照している" {
  # AC: 既存 gh issue create 呼び出しを新 script に migrate (co-issue / observer 起票 path)
  # RED: migrate 前は issue-create-refined.sh への参照が存在しない
  local co_issue_script="$REPO_ROOT/scripts/co-issue-manual-fix-b.sh"
  [[ -f "$co_issue_script" ]] || {
    echo "SKIP-FAIL: $co_issue_script が存在しない" >&2
    return 1
  }
  grep -q "issue-create-refined" "$co_issue_script" || {
    echo "FAIL: co-issue-manual-fix-b.sh が issue-create-refined.sh を参照していない（未 migrate）" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC2: observer 起票 path (spawn-controller.sh) が issue-create-refined.sh を利用している
# ---------------------------------------------------------------------------

@test "ac2: observer spawn-controller.sh が issue-create-refined.sh を参照している" {
  # AC: observer 起票 path も新 script に migrate する
  # RED: migrate 前は参照が存在しない
  local spawn_script="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  [[ -f "$spawn_script" ]] || {
    echo "SKIP-FAIL: $spawn_script が存在しない" >&2
    return 1
  }
  grep -q "issue-create-refined" "$spawn_script" || {
    echo "FAIL: spawn-controller.sh が issue-create-refined.sh を参照していない（未 migrate）" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: .github/workflows/auto-refined.yml が存在する
# ---------------------------------------------------------------------------

@test "ac3: .github/workflows/auto-refined.yml が存在する" {
  # AC: GitHub Actions (Approach C) で fallback 自動化 (tech-debt label 検出 → Refined 遷移)
  # RED: 実装前はファイル未作成
  # REPO_ROOT は plugins/twl/ → ../../.. で bare repo worktree ルートに到達する
  local project_root
  project_root="$(cd "$REPO_ROOT/../.." && pwd)"
  local workflow="${project_root}/.github/workflows/auto-refined.yml"
  [[ -f "$workflow" ]] || {
    echo "FAIL: $workflow が存在しない（未実装）" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC3: auto-refined.yml が tech-debt label を検出して Refined 遷移を行う定義を含む
# ---------------------------------------------------------------------------

@test "ac3: auto-refined.yml が tech-debt label 検出と Refined 遷移ステップを含む" {
  # AC: tech-debt label 検出 → Refined 遷移の GitHub Actions 定義
  # RED: 実装前は定義が存在しない
  local project_root
  project_root="$(cd "$REPO_ROOT/../.." && pwd)"
  local workflow="${project_root}/.github/workflows/auto-refined.yml"
  if [[ ! -f "$workflow" ]]; then
    echo "FAIL: $workflow が存在しない" >&2
    return 1
  fi
  grep -q "tech-debt" "$workflow" || {
    echo "FAIL: auto-refined.yml に tech-debt label 検出の定義がない" >&2
    return 1
  }
  grep -q "Refined" "$workflow" || {
    echo "FAIL: auto-refined.yml に Refined 遷移の定義がない" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# AC4: smoke — issue-create-refined.sh が存在すれば autopilot gate 通過可能（存在確認）
# ---------------------------------------------------------------------------

@test "ac4: smoke — issue-create-refined.sh が存在し autopilot gate を通過できる前提を満たす" {
  # AC: Wave 54+ で bug Issue 起票 → autopilot spawn が手動介入なしで通過することを確認
  # RED: issue-create-refined.sh 未実装のため前提を満たせない
  local script="$REPO_ROOT/scripts/issue-create-refined.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない。autopilot gate が Refined 未設定で reject するリスクあり（未実装）" >&2
    return 1
  }
  # --dry-run フラグで実際の gh 呼び出しをスキップして終了コードのみ検証
  stub_command "gh" 'echo "1469"'
  run bash "$script" --dry-run 2>/dev/null || true
  # dry-run が実装されていない場合も fail → RED 維持
  [[ "$status" -eq 0 ]] || {
    echo "FAIL: issue-create-refined.sh --dry-run が非ゼロで終了（未実装または --dry-run 未対応）" >&2
    return 1
  }
}
