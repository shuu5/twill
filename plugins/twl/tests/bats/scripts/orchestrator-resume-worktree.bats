#!/usr/bin/env bats
# orchestrator-resume-worktree.bats — Issue #1495
#
# Spec: orchestrator が exit 144 等で異常終了 → resume mode で再起動した際、
#       既存 worktree (bare_root/worktrees/) を「resume」として正しく認識し、
#       status=running/merge-ready を上書きせず Worker spawn を skip する。
#
# Coverage:
#   AC1: launch_worker の bare_root_dir 解決 helper `_resolve_bare_root_dir` が main/.git ファイル
#        worktree mode を検出し、親ディレクトリ (= bare_root) を返す
#   AC2: filter_active_issues で status=running + worktree existing in bare_root → ACTIVE_ENTRIES から除外
#
# §9 heredoc チェック: heredoc 内で外部変数を参照しない。
# §10 source guard チェック: orchestrator.sh は source guard を持たない。直接 source 禁止。

load '../helpers/common'

ORCHESTRATOR_SH=""

setup() {
  common_setup
  ORCHESTRATOR_SH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: _resolve_bare_root_dir helper の動作検証
# ---------------------------------------------------------------------------

@test "AC1-a: _resolve_bare_root_dir が main/.git ファイル worktree mode で親ディレクトリを返す" {
  # Given: bare repo worktree 構造
  mkdir -p "$SANDBOX/twill-test/main"
  mkdir -p "$SANDBOX/twill-test/.bare"
  echo "gitdir: $SANDBOX/twill-test/.bare" > "$SANDBOX/twill-test/main/.git"

  # When: helper を呼ぶ (bash 関数を抽出して直接 source)
  run bash -c "source <(grep -A 9 '^_resolve_bare_root_dir()' '$ORCHESTRATOR_SH'); _resolve_bare_root_dir '$SANDBOX/twill-test/main'"

  # Then: 親ディレクトリ (bare_root) が返る
  assert_success
  assert_output "$SANDBOX/twill-test"
}

@test "AC1-b: _resolve_bare_root_dir が standalone repo (.git ディレクトリ) で同ディレクトリを返す" {
  # Given: standalone repo (.git はディレクトリ)
  mkdir -p "$SANDBOX/standalone/.git"

  # When
  run bash -c "source <(grep -A 9 '^_resolve_bare_root_dir()' '$ORCHESTRATOR_SH'); _resolve_bare_root_dir '$SANDBOX/standalone'"

  # Then: 同ディレクトリが返る (worktrees/ は project_dir 直下)
  assert_success
  assert_output "$SANDBOX/standalone"
}

# ---------------------------------------------------------------------------
# AC2: filter_active_issues の resume フィルタ
# ---------------------------------------------------------------------------

@test "AC2-a: orchestrator.sh が L293 で _bare_root_dir/worktrees/ を参照する (静的 grep)" {
  # 静的検証: L293 周辺で _bare_root_dir を使用していること
  run grep -E 'skip_candidate_dir="\$_bare_root_dir/worktrees/' "$ORCHESTRATOR_SH"
  assert_success
  assert_output --partial '_bare_root_dir/worktrees/'
}

@test "AC2-b: orchestrator.sh が L316 で _bare_root_dir/worktrees/ を参照する (静的 grep)" {
  # 静的検証: L316 周辺で _bare_root_dir を使用していること
  run grep -E 'candidate_dir="\$_bare_root_dir/worktrees/\$existing_branch"' "$ORCHESTRATOR_SH"
  assert_success
  assert_output --partial '_bare_root_dir/worktrees/'
}

@test "AC2-c: filter_active_issues 内に running/merge-ready resume フィルタが存在する (静的 grep)" {
  # 静的検証: filter_active_issues 関数内に「resume worktree skip」logic が存在
  run grep -E 'status.*running.*merge-ready.*' "$ORCHESTRATOR_SH"
  assert_success

  # 「worktree active in bare_root」のメッセージが存在
  run grep -E 'worktree active in bare_root' "$ORCHESTRATOR_SH"
  assert_success
}

@test "AC2-d: filter_active_issues 修正前と異なる挙動 (regression sentinel)" {
  # 静的検証: effective_project_dir/worktrees/ への参照が完全に削除されていること
  # (もし残っていれば bug 1-A が再発)
  run grep -nE 'effective_project_dir/worktrees/' "$ORCHESTRATOR_SH"
  assert_failure  # 参照が無いことを確認
}

# ---------------------------------------------------------------------------
# AC1+AC2 統合: helper 関数定義の存在確認
# ---------------------------------------------------------------------------

@test "AC-helper: _resolve_bare_root_dir 関数が定義されている" {
  run grep -E '^_resolve_bare_root_dir\(\)' "$ORCHESTRATOR_SH"
  assert_success
  assert_output --partial '_resolve_bare_root_dir()'
}

@test "AC-helper: _resolve_bare_root_dir が main/.git ファイル分岐を持つ" {
  # _resolve_bare_root_dir 関数本体に `[[ -f "$_project_dir/.git" ]]` のチェックがあること
  run grep -E '\-f "\$_project_dir/\.git"' "$ORCHESTRATOR_SH"
  assert_success
}
