#!/usr/bin/env bats
# pre-bash-issue-create-gate.bats — AC2 RED テストスタブ
#
# Issue #1578: feat(supervisor): Issue 起票前 co-explore 強制 enforcement
# AC2: pre-bash-issue-create-gate.sh 実装 + bats 12 シナリオ (S1-S12 全 PASS)
#
# 対象ファイル（未実装）:
#   plugins/twl/scripts/hooks/pre-bash-issue-create-gate.sh  (REPO_ROOT相対: scripts/hooks/...)
#
# RED: 対象スクリプトが存在しないため全シナリオが fail する（意図的 RED フェーズ）
#
# Scenarios:
#   S1:  gh issue create + CO_EXPLORE_DONE 未設定 → deny
#   S2:  gh issue create + CO_EXPLORE_DONE=1 → allow
#   S3:  gh issue create + explore-summary ファイル存在 → allow
#   S4:  gh issue create --template を含む → deny（template 指定も gate 対象）
#   S5:  gh issue create + CO_EXPLORE_DONE=1 + --repo 指定 → allow（cross-repo も通過）
#   S6:  gh pr create → allow（gate 対象外コマンド）
#   S7:  gh issue list → allow（gate 対象外コマンド）
#   S8:  git commit → allow（gh issue create でないため対象外）
#   S9:  gh issue create + CO_EXPLORE_SKIP=1 → deny（SKIP env は gate を bypass しない）
#   S10: gh issue create + 空白コマンド prefix → deny（前置き空白あっても検知）
#   S11: gh issue create --body "..." + CO_EXPLORE_DONE 未設定 → deny + actionable message
#   S12: gh issue create + explore-summary ファイルなし + CO_EXPLORE_DONE 未設定 → deny + summary path を含むメッセージ

load '../helpers/common'

GATE_SCRIPT="scripts/hooks/pre-bash-issue-create-gate.sh"

setup() {
  common_setup

  # REPO_ROOT は common.bash で解決済み（= plugins/twl/ を指す）
  GATE_PATH="$REPO_ROOT/$GATE_SCRIPT"

  # explore-summary 用ディレクトリ
  mkdir -p "$SANDBOX/.explore"

  # gate が未実装の場合は全テストで false になる（RED）
  # 実装後はスクリプトが SANDBOX/scripts/ へコピーされた状態でテストされる
}

teardown() {
  unset CO_EXPLORE_DONE CO_EXPLORE_SKIP
  common_teardown
}

# ---------------------------------------------------------------------------
# S1: gh issue create + CO_EXPLORE_DONE 未設定 → deny
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_DONE が設定されておらず gh issue create を実行しようとする
# THEN: exit 2 (PreToolUse deny) で block される
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S1: gh issue create + CO_EXPLORE_DONE 未設定 → deny" {
  # RED: gate スクリプトが存在しないため fail
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh issue create --title 'test' --body 'body'" \
    run bash "$GATE_PATH"

  assert_failure
}

# ---------------------------------------------------------------------------
# S2: gh issue create + CO_EXPLORE_DONE=1 → allow
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_DONE=1 が設定された状態で gh issue create を実行しようとする
# THEN: exit 0 で allow される
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S2: gh issue create + CO_EXPLORE_DONE=1 → allow" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  CO_EXPLORE_DONE=1 \
  TOOL_INPUT_command="gh issue create --title 'test' --body 'body'" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S3: gh issue create + explore-summary ファイル存在 → allow
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_DONE は未設定だが explore-summary ファイルが存在する
# THEN: exit 0 で allow される（ファイル存在が証跡になる）
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S3: gh issue create + explore-summary ファイル存在 → allow" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  # explore-summary を作成（証跡ファイル）
  mkdir -p "$SANDBOX/.explore/99"
  echo '{"summary": "test"}' > "$SANDBOX/.explore/99/summary.md"

  unset CO_EXPLORE_DONE

  CO_EXPLORE_SUMMARY_DIR="$SANDBOX/.explore" \
  TOOL_INPUT_command="gh issue create --title 'test' --body 'body'" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S4: gh issue create --template → deny（template 指定も gate 対象）
# ---------------------------------------------------------------------------

# WHEN: --template オプション付きでも CO_EXPLORE_DONE 未設定
# THEN: deny（template 付きでも issue 起票は gate を通る）
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S4: gh issue create --template + CO_EXPLORE_DONE 未設定 → deny" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh issue create --template bug_report.md --title 'bug'" \
    run bash "$GATE_PATH"

  assert_failure
}

# ---------------------------------------------------------------------------
# S5: gh issue create + CO_EXPLORE_DONE=1 + --repo 指定 → allow
# ---------------------------------------------------------------------------

# WHEN: cross-repo (--repo owner/repo) 指定 + CO_EXPLORE_DONE=1
# THEN: allow（cross-repo でも env marker が有効）
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S5: gh issue create + CO_EXPLORE_DONE=1 + --repo 指定 → allow (cross-repo)" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  CO_EXPLORE_DONE=1 \
  TOOL_INPUT_command="gh issue create --repo shuu5/other-repo --title 'cross' --body 'b'" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S6: gh pr create → allow（gate 対象外コマンド）
# ---------------------------------------------------------------------------

# WHEN: gh pr create を実行しようとする
# THEN: gate は対象外として allow
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S6: gh pr create → allow (gate 対象外)" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh pr create --title 'feat' --body 'desc'" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S7: gh issue list → allow（gate 対象外コマンド）
# ---------------------------------------------------------------------------

# WHEN: gh issue list を実行しようとする
# THEN: gate は対象外として allow
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S7: gh issue list → allow (gate 対象外)" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh issue list --state open" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S8: git commit → allow（gh issue create でないため対象外）
# ---------------------------------------------------------------------------

# WHEN: git commit を実行しようとする
# THEN: gate は対象外として allow
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S8: git commit → allow (gh issue create でない)" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="git commit -m 'feat: add feature'" \
    run bash "$GATE_PATH"

  assert_success
}

# ---------------------------------------------------------------------------
# S9: gh issue create + CO_EXPLORE_SKIP=1 → deny（SKIP env は bypass しない）
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_SKIP=1 が設定されているが CO_EXPLORE_DONE は未設定
# THEN: deny（SKIP は gate bypass には使用できない。CO_EXPLORE_DONE のみが許可証）
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S9: gh issue create + CO_EXPLORE_SKIP=1 (CO_EXPLORE_DONE 未設定) → deny" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE
  CO_EXPLORE_SKIP=1 \
  TOOL_INPUT_command="gh issue create --title 'skip test' --body 'body'" \
    run bash "$GATE_PATH"

  assert_failure
}

# ---------------------------------------------------------------------------
# S10: gh issue create（前置き空白あり）→ deny
# ---------------------------------------------------------------------------

# WHEN: コマンド文字列に前置き空白がある場合も gh issue create として検知される
# THEN: deny（前置きスペース・タブがあっても正規化して検知する）
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S10: '  gh issue create' (先頭空白) + CO_EXPLORE_DONE 未設定 → deny" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="  gh issue create --title 'trimmed' --body 'body'" \
    run bash "$GATE_PATH"

  assert_failure
}

# ---------------------------------------------------------------------------
# S11: gh issue create + CO_EXPLORE_DONE 未設定 → deny + actionable message
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_DONE が未設定で gh issue create を実行しようとする
# THEN: exit 2 (deny) かつ actionable message（co-explore 手順の案内）を stdout/stderr に出力
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S11: gh issue create + CO_EXPLORE_DONE 未設定 → deny + actionable message 出力" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh issue create --title 'new feat' --body 'feature description'" \
    run bash "$GATE_PATH"

  assert_failure
  # actionable message: co-explore への案内が含まれること
  assert_output --partial "co-explore"
}

# ---------------------------------------------------------------------------
# S12: gh issue create + summary なし + CO_EXPLORE_DONE 未設定 → deny + summary path 言及
# ---------------------------------------------------------------------------

# WHEN: CO_EXPLORE_DONE 未設定かつ explore-summary も存在しない
# THEN: deny かつ summary の期待パス（.explore/<N>/summary.md 等）を含むメッセージ
# RED: pre-bash-issue-create-gate.sh が未実装のため fail
@test "S12: gh issue create + summary なし → deny + summary path 言及" {
  [ -f "$GATE_PATH" ] || {
    false  # RED: gate 未実装
  }

  unset CO_EXPLORE_DONE

  TOOL_INPUT_command="gh issue create --title 'no-summary' --body 'body'" \
    run bash "$GATE_PATH"

  assert_failure
  # summary ファイルパスへの言及が含まれること
  assert_output --partial ".explore"
}
