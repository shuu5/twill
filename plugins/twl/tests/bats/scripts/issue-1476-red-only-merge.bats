#!/usr/bin/env bats
# issue-1476-red-only-merge.bats — RED-phase tests for Issue #1476
#
# Issue #1476: Wave 54 でmerged されたPR #1470 (closes #1469) は RED bats test のみを追加し、
# issue-create-refined.sh の実装が完全に欠落したまま merge された。
# merge-gate が "RED-only PR"（テストファイルのみで実装ファイルなし）を検出して reject する。
#
# AC coverage:
#   AC1 - merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
#   AC2 - bats test で diff = test only PR を simulate → reject 動作確認
#   AC4 - PR #1470 でmerged された bats test の expected 実装が main に存在することを確認

load '../helpers/common'

setup() {
  common_setup
  export CLAUDE_PLUGIN_ROOT="$SANDBOX"
  export ISSUE_NUM="1476"

  stub_command "git" '
    case "$*" in
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*) echo ".git" ;;
      *"branch --show-current"*) echo "feat/1476-test" ;;
      *"diff --name-only"*)
        # デフォルト: テストファイルのみ（RED-only PR を simulate）
        echo "plugins/twl/tests/bats/scripts/issue-create-refined.bats"
        ;;
      *) exit 0 ;;
    esac
  '

  stub_command "gh" '
    case "$*" in
      *"pr view"*"--json number"*) echo "1470" ;;
      *) exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: merge-gate specialist で "RED-only PR" を検出して reject
# ---------------------------------------------------------------------------

@test "ac1: merge-gate-check-red-only.sh が scripts/ に存在する" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: 実装前は fail する（ファイル未作成）
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }
}

@test "ac1: merge-gate-check-red-only.sh が実行可能である" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }
  [[ -x "$script" ]] || {
    echo "FAIL: $script が実行可能でない" >&2
    return 1
  }
}

@test "ac1: merge-gate-check-red-only.sh が bash 構文チェック pass" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: ファイル未存在のため fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }
  bash -n "$script"
}

@test "ac1: diff がテストファイルのみの場合 REJECT メッセージを出力する" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }

  # テストファイルのみの diff を simulate
  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        echo "plugins/twl/tests/bats/scripts/issue-create-refined.bats"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script" 2>&1

  assert_output --partial "REJECT"
}

@test "ac1: diff がテストファイルのみの場合 exit 1 を返す" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        echo "plugins/twl/tests/bats/scripts/issue-create-refined.bats"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script"

  assert_failure
}

@test "ac1: diff に実装ファイルが含まれる場合は exit 0 を返す" {
  # AC: merge-gate specialist で "RED-only PR" を検出して reject (Approach 1)
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  # テストファイル + 実装ファイルの diff を simulate
  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        echo "plugins/twl/tests/bats/scripts/issue-create-refined.bats"
        echo "plugins/twl/scripts/issue-create-refined.sh"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script"

  assert_success
}

@test "ac1: diff が実装ファイルのみ（テストなし）の場合は exit 0 を返す（テストなし自体は reject しない）" {
  # AC: 実装ファイルのみの場合は問題なし
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        echo "plugins/twl/scripts/issue-create-refined.sh"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script"

  assert_success
}

# ---------------------------------------------------------------------------
# AC2: bats test で diff = test only PR を simulate → reject 動作確認
# ---------------------------------------------------------------------------

@test "ac2: テストファイルのみの diff で RED-only を検出できる" {
  # AC: bats test で diff = test only PR を simulate → reject 動作確認
  # RED: 実装前は fail する（スクリプト未存在）
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない。RED-only PR 検出機能が未実装" >&2
    return 1
  }

  # .bats ファイルのみの diff を simulate（PR #1470 相当）
  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        printf "plugins/twl/tests/bats/scripts/issue-create-refined.bats\n"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script" 2>&1

  assert_failure
  assert_output --partial "REJECT"
}

@test "ac2: .bats ファイル群のみを含む diff で RED-only と判定される" {
  # AC: bats test で diff = test only PR を simulate → reject 動作確認
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  # 複数の bats ファイルのみの diff
  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        printf "plugins/twl/tests/bats/scripts/foo.bats\nplugins/twl/tests/bats/scripts/bar.bats\n"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script"

  assert_failure
}

@test "ac2: テスト + 実装ファイルを含む diff では RED-only と判定されない" {
  # AC: bats test で diff = test only PR を simulate → reject 動作確認
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/merge-gate-check-red-only.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  stub_command "git" '
    case "$*" in
      *"diff --name-only"*|*"diff HEAD"*)
        printf "plugins/twl/tests/bats/scripts/issue-create-refined.bats\nplugins/twl/scripts/issue-create-refined.sh\n"
        ;;
      *) exit 0 ;;
    esac
  '

  run bash "$script"

  assert_success
}

# ---------------------------------------------------------------------------
# AC4: PR #1470 でmerged された bats test の expected 実装が main に存在することを確認
# ---------------------------------------------------------------------------

@test "ac4: issue-create-refined.sh が scripts/ に存在する" {
  # AC: PR #1470 でmerged された bats test の expected 実装が main に存在することを確認
  # RED: issue-create-refined.sh が未実装のため fail する
  local script="$REPO_ROOT/scripts/issue-create-refined.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない" >&2
    echo "INFO: PR #1470 は issue-create-refined.bats を追加したが、実装 issue-create-refined.sh は merge されていない" >&2
    return 1
  }
}

@test "ac4: issue-create-refined.sh が実行可能である" {
  # AC: PR #1470 でmerged された bats test の expected 実装が main に存在することを確認
  # RED: 実装前は fail する
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

@test "ac4: issue-create-refined.sh が bash 構文チェック pass" {
  # AC: PR #1470 でmerged された bats test の expected 実装が main に存在することを確認
  # RED: 実装前は fail する
  local script="$REPO_ROOT/scripts/issue-create-refined.sh"
  [[ -f "$script" ]] || {
    echo "FAIL: $script が存在しない（未実装）" >&2
    return 1
  }
  bash -n "$script"
}

@test "ac4: issue-create-refined.sh が gh issue create と Refined 遷移を実行する" {
  # AC: PR #1470 でmerged された bats test の expected 実装が main に存在することを確認
  # RED: 実装前は fail する
  local script="$SANDBOX/scripts/issue-create-refined.sh"
  [[ -f "$script" ]] || {
    false
    return
  }

  local call_log="$SANDBOX/gh_calls.log"
  stub_command "gh" "echo \"\$*\" >> '$call_log'; echo '1469'"

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
