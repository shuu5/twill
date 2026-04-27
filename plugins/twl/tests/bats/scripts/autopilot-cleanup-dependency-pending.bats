#!/usr/bin/env bats
# autopilot-cleanup-dependency-pending.bats
# AC: Issue #997 — autopilot-cleanup が依存解決中の state file を archive しない
#
# Scenarios:
#   AC1: is_in_dependency_chain 相当の判定ロジックが autopilot-cleanup.sh に存在する
#   AC2: Phase 1 完了直後（Phase 2 が依存、まだ running）→ Phase 1 state file は archive されない
#   AC4: Phase 2 完了後の再 cleanup → Phase 1 state file が archive される
#   AC_compat: plan.yaml 不在時は既存挙動（即 archive）を維持する
#
# スタイル: orchestrator-cleanup-sequence.bats / archive-removal.bats 準拠
# RED phase: AC1・AC2 のテストが実装前は FAIL する

load '../helpers/common'

# ---------------------------------------------------------------------------
# Helper: plan.yaml を sandbox .autopilot/ に生成する
# Phase 2 が Phase 1 に依存する 2 フェーズ構成
# format は autopilot-plan.sh / autopilot-should-skip.sh に準拠
# ---------------------------------------------------------------------------
_create_plan_yaml_phase1_phase2() {
  local phase1_issue="$1"
  local phase2_issue="$2"
  cat > "$SANDBOX/.autopilot/plan.yaml" <<EOF
session_id: "test-session"
repo_mode: "worktree"
project_dir: "$SANDBOX"
phases:
  - phase: 1
  - ${phase1_issue}
  - phase: 2
  - ${phase2_issue}
dependencies:
  ${phase2_issue}:
  - ${phase1_issue}
EOF
}

# Helper: 複数 Phase 1 issue が 1 Phase 2 issue に依存する場合
_create_plan_yaml_multi_phase1() {
  local phase2_issue="$1"
  shift
  local phase1_issues=("$@")

  {
    echo "session_id: \"test-session\""
    echo "repo_mode: \"worktree\""
    echo "project_dir: \"$SANDBOX\""
    echo "phases:"
    echo "  - phase: 1"
    for p1 in "${phase1_issues[@]}"; do
      echo "  - ${p1}"
    done
    echo "  - phase: 2"
    echo "  - ${phase2_issue}"
    echo "dependencies:"
    echo "  ${phase2_issue}:"
    for p1 in "${phase1_issues[@]}"; do
      echo "  - ${p1}"
    done
  } > "$SANDBOX/.autopilot/plan.yaml"
}

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: is_in_dependency_chain 相当のロジックが autopilot-cleanup.sh に存在する
# RED: 現在は実装されていないため失敗する
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC1]: is_in_dependency_chain 相当のロジックが実装されている" {
  # AC: autopilot-cleanup.sh に is_in_dependency_chain 相当の判定関数が実装され、
  #     plan.yaml の dependencies: セクションを参照する
  run grep -qE "is_in_dependency_chain|dependency.chain|dependency.pending" \
    "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

@test "cleanup[dependency][AC1]: plan.yaml の dependencies セクションを参照している" {
  # AC: plan.yaml の dependencies: セクションを参照する実装が存在する
  run grep -q "dependencies" "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# AC2: Phase 1 done + Phase 2 running → Phase 1 は archive されない
# RED: 現在は done を即 archive するため失敗する
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC2]: Phase2が依存するPhase1のdone issueはPhase2完了前にarchiveされない" {
  # GIVEN: Phase 1 issue (done), Phase 2 issue (running, depends on Phase 1)
  create_issue_json 100 "done"
  create_issue_json 200 "running"
  _create_plan_yaml_phase1_phase2 100 200

  # WHEN: cleanup 実行
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # THEN: Phase 1 issue は .autopilot/issues/ に残っていること
  [ -f "$SANDBOX/.autopilot/issues/issue-100.json" ]
}

@test "cleanup[dependency][AC2]: Phase2依存中のPhase1スキップログが出力される" {
  create_issue_json 100 "done"
  create_issue_json 200 "running"
  _create_plan_yaml_phase1_phase2 100 200

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  # スキップログに dependency-pending の記述があること
  assert_output --partial "dependency-pending"
}

@test "cleanup[dependency][AC2]: 複数Phase1 issueが全てPhase2完了前はarchiveされない" {
  create_issue_json 101 "done"
  create_issue_json 102 "done"
  create_issue_json 103 "done"
  create_issue_json 200 "running"
  _create_plan_yaml_multi_phase1 200 101 102 103

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # 全 Phase 1 issue が issues/ に残っていること
  [ -f "$SANDBOX/.autopilot/issues/issue-101.json" ]
  [ -f "$SANDBOX/.autopilot/issues/issue-102.json" ]
  [ -f "$SANDBOX/.autopilot/issues/issue-103.json" ]
}

@test "cleanup[dependency][AC2]: Phase2がpendingステータスの場合もPhase1はarchiveされない" {
  create_issue_json 100 "done"
  create_issue_json 200 "pending"
  _create_plan_yaml_phase1_phase2 100 200

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  [ -f "$SANDBOX/.autopilot/issues/issue-100.json" ]
}

# ---------------------------------------------------------------------------
# AC3: 後続 Phase 起動時に dependency 確認が成功する
# (AC2 の裏返し: issue-100.json が .autopilot/issues/ に残っていれば
#  autopilot-should-skip.sh の依存解決ロジックが正常動作する)
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC3]: Phase1 issueが残存することでPhase2のdep解決が成功する" {
  create_issue_json 100 "done"
  create_issue_json 200 "running"
  _create_plan_yaml_phase1_phase2 100 200

  # cleanup 実行後 Phase 1 issue が残っていることで
  # autopilot-should-skip.sh が Phase 2 を "skip せず実行" と判断できる
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"
  assert_success

  # Phase 1 の state file が issues/ に存在すること（dep 解決に必要）
  [ -f "$SANDBOX/.autopilot/issues/issue-100.json" ]

  # autopilot-should-skip.sh が "実行 (exit 1)" と判断すること
  # （200 の dep 先 100 が done かつ issues/ に存在する）
  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 200
  # exit 1 = "実行" を示す（should-skip の仕様）
  assert_failure
}

# ---------------------------------------------------------------------------
# AC4: Phase 2 完了後の cleanup 再実行 → Phase 1 は archive される
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC4]: Phase2完了後の再cleanup でPhase1 issueがarchiveされる" {
  # GIVEN: Phase 1 done + Phase 2 done（全フェーズ完了）
  create_issue_json 100 "done"
  create_issue_json 200 "done"
  _create_plan_yaml_phase1_phase2 100 200

  # WHEN: cleanup 実行（Phase 2 完了後）
  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # THEN: Phase 1 issue は archive されること
  [ ! -f "$SANDBOX/.autopilot/issues/issue-100.json" ]
  # archive ディレクトリに移動されていること
  local archive_files
  archive_files=$(find "$SANDBOX/.autopilot/archive" -name "issue-100.json" 2>/dev/null)
  [ -n "$archive_files" ]
}

@test "cleanup[dependency][AC4]: Phase2もdoneならPhase2もarchiveされる" {
  create_issue_json 100 "done"
  create_issue_json 200 "done"
  _create_plan_yaml_phase1_phase2 100 200

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  [ ! -f "$SANDBOX/.autopilot/issues/issue-200.json" ]
}

# ---------------------------------------------------------------------------
# AC_compat: plan.yaml 不在時の後方互換（既存挙動: 即 archive）
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC_compat]: plan.yaml不在の場合はdone issueを即archiveする" {
  # plan.yaml なし（古い session・直接 launch）
  create_issue_json 100 "done"
  # plan.yaml は作成しない

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # 既存挙動: done → 即 archive
  [ ! -f "$SANDBOX/.autopilot/issues/issue-100.json" ]
}

@test "cleanup[dependency][AC_compat]: plan.yaml不在でもarchive先に移動されている" {
  create_issue_json 100 "done"

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  local archive_files
  archive_files=$(find "$SANDBOX/.autopilot/archive" -name "issue-100.json" 2>/dev/null)
  [ -n "$archive_files" ]
}

# ---------------------------------------------------------------------------
# AC6: 既存テストへの影響なし（回帰テスト用マーカー）
# このテストファイル自体では orchestrator-cleanup-sequence.bats と
# archive-removal.bats の pass/fail は検証しない（CI で別途実行）
# ---------------------------------------------------------------------------

@test "cleanup[dependency][AC_compat]: dependenciesが空のplan.yamlでもdone issueをarchiveする" {
  create_issue_json 100 "done"
  # dependencies セクションが空の plan.yaml（単一フェーズ）
  cat > "$SANDBOX/.autopilot/plan.yaml" <<EOF
session_id: "test-session"
phases:
  - phase: 1
  - 100
dependencies:
EOF

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success
  [ ! -f "$SANDBOX/.autopilot/issues/issue-100.json" ]
}
