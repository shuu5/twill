#!/usr/bin/env bats
# ac-scaffold-tests-1564.bats - Issue #1564 AC チェックリスト RED テスト
#
# Issue #1564: docs/adr-024: refine evidence phase (Phase D 補遺)
# mode=red: 全テストが実装前に fail することを意図している
#
# AC1: ADR-024 に Phase D セクションが存在し、必須コンテンツが含まれる
# AC2: ADR-024 Phase D 補遺内に Phase4-complete.json JSON schema が含まれる
# AC3: co-issue-phase4-aggregate.md [B] path に Phase4-complete.json 生成 step が含まれる
# AC4: co-issue-phase4-aggregate.md [D] path に Phase4-complete.json 生成 step が含まれる
# AC5: co-issue-cleanup.md に Phase4-complete.json cleanup 方針が含まれる
# AC6: 各ソースファイルの該当行に ADR-024 Phase D 参照が含まれる
# AC7: co-issue-phase4-evidence-generation.bats が存在する
# AC8: ADR-024 Phase D 補遺に schema_version breaking change 方針が含まれる

load '../helpers/common'

ADR024_PATH="plugins/twl/architecture/decisions/ADR-024-refined-status-field-migration.md"
PHASE4_AGGREGATE_PATH="plugins/twl/skills/co-issue/refs/co-issue-phase4-aggregate.md"
CLEANUP_PATH="plugins/twl/skills/co-issue/refs/co-issue-cleanup.md"
HOOK_PATH="plugins/twl/scripts/hooks/pre-bash-refined-status-gate.sh"
TOOLS_PY_PATH="cli/twl/src/twl/mcp_server/tools.py"

setup() {
  common_setup
  # REPO_ROOT は common.bash で設定 (tests/../ = plugins/twl)
  # リポジトリルートは REPO_ROOT/../../.. = worktree root
  GIT_ROOT="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"
  export GIT_ROOT
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: ADR-024 に Phase D セクション (Phase C の後) が存在する
# RED: Phase D セクションは未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac1: ADR-024 に Phase D (2026-05-12) 補遺セクションが存在する" {
  # AC: ADR-024-refined-status-field-migration.md に Phase D セクションが存在すること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qF "Phase D" "$adr_file"
  assert_success
}

@test "ac1: ADR-024 Phase D セクションが Phase C の後に配置されている" {
  # AC: Phase D が Phase C の後に配置されること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  local phase_c_line phase_d_line
  phase_c_line=$(grep -n "Phase C" "$adr_file" | head -1 | cut -d: -f1)
  phase_d_line=$(grep -n "Phase D" "$adr_file" | head -1 | cut -d: -f1)
  [[ -n "$phase_c_line" && -n "$phase_d_line" && "$phase_d_line" -gt "$phase_c_line" ]]
}

@test "ac1: ADR-024 Phase D 補遺に evidence taxonomy が含まれる" {
  # AC: evidence taxonomy (3 種) の記述が含まれること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qF "spec-review-session" "$adr_file"
  assert_success
  run grep -qF "Phase4-complete.json" "$adr_file"
  assert_success
  run grep -qF "refined" "$adr_file"
  assert_success
}

@test "ac1: ADR-024 Phase D 補遺に cross-repo Issue 適用範囲の記述が含まれる" {
  # AC: cross-repo Issue への適用範囲が記述されること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qE "cross.?repo" "$adr_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC2: ADR-024 Phase D 補遺に Phase4-complete.json JSON schema が含まれる
# RED: Phase D セクションは未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac2: ADR-024 Phase D 補遺に schema_version=1.0.0 が含まれる" {
  # AC: schema_version=1.0.0 として正典化された schema の記述
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qF "schema_version" "$adr_file"
  assert_success
  run grep -qF "1.0.0" "$adr_file"
  assert_success
}

@test "ac2: ADR-024 Phase D 補遺に Phase4-complete.json の必須フィールドがすべて含まれる" {
  # AC: 必須フィールド: schema_version, session_id, issue_number, repo, completed_at, specialists, phase4_path
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  for field in schema_version session_id issue_number repo completed_at specialists phase4_path; do
    run grep -qF "\"$field\"" "$adr_file"
    assert_success
  done
}

@test "ac2: ADR-024 Phase D 補遺に Markdown コードブロックで schema が記述されている" {
  # AC: JSON schema が Markdown コードブロック内に記述されること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  # json コードブロックが存在すること
  run grep -qF '```json' "$adr_file"
  assert_success
}

@test "ac2: ADR-024 Phase D 補遺に Phase4-complete.json 生成パスの記述が含まれる" {
  # AC: Phase4-complete.json の生成パス (${CONTROLLER_ISSUE_DIR}/${SESSION_ID}/Phase4-complete.json) が記述されること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qF "Phase4-complete.json" "$adr_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC3: co-issue-phase4-aggregate.md [B] path に Phase4-complete.json 生成 step が含まれる
# RED: [B] path に生成 step は未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac3: co-issue-phase4-aggregate.md [B] path に Phase4-complete.json 生成 step が含まれる" {
  # AC: [B] manual fix path に Phase4-complete.json 生成 step が追加されること
  # RED: 生成 step は未追加
  local aggregate_file="$GIT_ROOT/$PHASE4_AGGREGATE_PATH"
  run grep -qF "Phase4-complete.json" "$aggregate_file"
  assert_success
}

@test "ac3: co-issue-phase4-aggregate.md [B] path の Phase4-complete.json 生成が board-status-update Refined の直前に配置される" {
  # AC: 生成タイミングは chain-runner.sh board-status-update Refined の直前
  # RED: 生成 step は未追加のため順序検証も fail する
  local aggregate_file="$GIT_ROOT/$PHASE4_AGGREGATE_PATH"
  local phase4_line board_update_line
  phase4_line=$(grep -n "Phase4-complete.json" "$aggregate_file" | grep -v "^\s*#" | head -1 | cut -d: -f1)
  board_update_line=$(grep -n "board-status-update.*Refined" "$aggregate_file" | head -1 | cut -d: -f1)
  # Phase4-complete.json 生成行が board-status-update Refined の前にあること
  [[ -n "$phase4_line" && -n "$board_update_line" && "$phase4_line" -lt "$board_update_line" ]]
}

# ---------------------------------------------------------------------------
# AC4: co-issue-phase4-aggregate.md [D] path に Phase4-complete.json 生成 step が含まれる
# RED: [D] path に生成 step は未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac4: co-issue-phase4-aggregate.md [D] direct specialist spawn path に Phase4-complete.json 生成 step が含まれる" {
  # AC: [D] path にも Phase4-complete.json 生成 step が追加されること
  # RED: 生成 step は未追加
  # NOTE: AC3 テストと区別するため [D] セクション内での検証
  local aggregate_file="$GIT_ROOT/$PHASE4_AGGREGATE_PATH"
  # [D] パス内に phase4_path が "[D]" と記述されていること
  run grep -qF '"[D]"' "$aggregate_file"
  assert_success
}

@test "ac4: co-issue-phase4-aggregate.md [D] path の Phase4-complete.json に phase4_path が [D] として記録される" {
  # AC: [D] path の Phase4-complete.json 生成時 phase4_path は "[D]" であること
  # RED: 生成 step は未追加
  local aggregate_file="$GIT_ROOT/$PHASE4_AGGREGATE_PATH"
  run grep -qF 'phase4_path' "$aggregate_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC5: co-issue-cleanup.md に Phase4-complete.json cleanup 方針が含まれる
# RED: cleanup 方針は未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac5: co-issue-cleanup.md に Phase4-complete.json cleanup 方針が含まれる" {
  # AC: Phase4-complete.json の cleanup 設計方針が追加されること
  # RED: cleanup 方針は未追加
  local cleanup_file="$GIT_ROOT/$CLEANUP_PATH"
  run grep -qF "Phase4-complete.json" "$cleanup_file"
  assert_success
}

@test "ac5: co-issue-cleanup.md の Phase4-complete.json cleanup 方針に TTL 24h が含まれる" {
  # AC: 要件 (a) TTL 24h が記述されること
  # RED: cleanup 方針は未追加
  local cleanup_file="$GIT_ROOT/$CLEANUP_PATH"
  run grep -qF "24h" "$cleanup_file"
  assert_success
}

@test "ac5: co-issue-cleanup.md の Phase4-complete.json cleanup 方針に並行セッション isolation が含まれる" {
  # AC: 要件 (b) 並行セッション isolation が記述されること
  # RED: cleanup 方針は未追加
  local cleanup_file="$GIT_ROOT/$CLEANUP_PATH"
  run grep -qE "isolation|並行.*セッション" "$cleanup_file"
  assert_success
}

@test "ac5: co-issue-cleanup.md の Phase4-complete.json cleanup 方針に autopilot 完了まで削除しない方針が含まれる" {
  # AC: 要件 (c) autopilot 完了まで削除しない が記述されること
  # RED: cleanup 方針は未追加
  local cleanup_file="$GIT_ROOT/$CLEANUP_PATH"
  run grep -qE "autopilot.*完了|完了.*削除しない" "$cleanup_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC6: 各ソースファイルの該当行に ADR-024 Phase D 参照が含まれる
# RED: 各ファイルの該当行は未更新のため fail する
# ---------------------------------------------------------------------------
@test "ac6: pre-bash-refined-status-gate.sh L13 に ADR-024 Phase D 参照が含まれる" {
  # AC: L13 コメントを「co-issue Phase 4 完了 evidence (ADR-024 Phase D schema_version=1.0.0)」に更新
  # RED: 現在の L13 は ADR-024 Phase D を参照していない
  local hook_file="$GIT_ROOT/$HOOK_PATH"
  run grep -qF "ADR-024 Phase D" "$hook_file"
  assert_success
}

@test "ac6: pre-bash-refined-status-gate.sh に schema_version=1.0.0 参照が含まれる" {
  # AC: L13 コメントに schema_version=1.0.0 が含まれること
  # RED: 現在のコメントは schema_version を参照していない
  local hook_file="$GIT_ROOT/$HOOK_PATH"
  run grep -qF "schema_version=1.0.0" "$hook_file"
  assert_success
}

@test "ac6: tools.py L1620 に ADR-024 Phase D schema 参照が含まれる" {
  # AC: L1620 を「ADR-024 Phase D schema (schema_version=1.0.0) で正典化された Phase4-complete.json evidence を check」に更新
  # RED: 現在の L1620 は ADR-024 Phase D を参照していない
  local tools_file="$GIT_ROOT/$TOOLS_PY_PATH"
  run grep -qF "ADR-024 Phase D schema" "$tools_file"
  assert_success
}

@test "ac6: tools.py L1642 に ADR-024 Phase D schema_version=1.0.0 参照が含まれる" {
  # AC: L1642 を「ADR-024 Phase D schema_version=1.0.0 で正典化済み」を含む形に更新
  # RED: 現在の L1642 は ADR-024 Phase D を参照していない
  local tools_file="$GIT_ROOT/$TOOLS_PY_PATH"
  run grep -qF "schema_version=1.0.0" "$tools_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC7: bats test ファイル co-issue-phase4-evidence-generation.bats が存在する
# RED: ファイル自体は未作成のため fail する
# ---------------------------------------------------------------------------
@test "ac7: co-issue-phase4-evidence-generation.bats が plugins/twl/tests/bats/scripts/ に存在する" {
  # AC: bats test ファイル新規追加
  # RED: ファイルは未作成
  local bats_file="$GIT_ROOT/plugins/twl/tests/bats/scripts/co-issue-phase4-evidence-generation.bats"
  [[ -f "$bats_file" ]]
}

@test "ac7: co-issue-phase4-evidence-generation.bats に E1 テストが含まれる" {
  # AC: E1 Phase 4 [B] 模擬実行後に Phase4-complete.json が生成される
  # RED: ファイルは未作成
  local bats_file="$GIT_ROOT/plugins/twl/tests/bats/scripts/co-issue-phase4-evidence-generation.bats"
  run grep -qF "E1" "$bats_file"
  assert_success
}

@test "ac7: co-issue-phase4-evidence-generation.bats に E2 テストが含まれる" {
  # AC: E2 生成された JSON が AC2 schema 必須フィールドをすべて含む
  # RED: ファイルは未作成
  local bats_file="$GIT_ROOT/plugins/twl/tests/bats/scripts/co-issue-phase4-evidence-generation.bats"
  run grep -qF "E2" "$bats_file"
  assert_success
}

@test "ac7: co-issue-phase4-evidence-generation.bats に E3 テストが含まれる" {
  # AC: E3 既存 R3 シナリオが回帰しない
  # RED: ファイルは未作成
  local bats_file="$GIT_ROOT/plugins/twl/tests/bats/scripts/co-issue-phase4-evidence-generation.bats"
  run grep -qF "E3" "$bats_file"
  assert_success
}

# ---------------------------------------------------------------------------
# AC8: ADR-024 Phase D 補遺に schema_version breaking change 方針が含まれる
# RED: Phase D セクションは未追加のため fail する
# ---------------------------------------------------------------------------
@test "ac8: ADR-024 Phase D 補遺に semver 後方互換方針 (1.x.y) が含まれる" {
  # AC: 1.x.y 後方互換の記述
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qE "1\.x\.y|1\\.x\\.y" "$adr_file"
  assert_success
}

@test "ac8: ADR-024 Phase D 補遺に semver 不互換方針 (2.x.y) が含まれる" {
  # AC: 2.x.y 不互換の記述
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qE "2\.x\.y|2\\.x\\.y" "$adr_file"
  assert_success
}

@test "ac8: ADR-024 Phase D 補遺に breaking change の記述が含まれる" {
  # AC: breaking change 方針が明記されること
  # RED: Phase D セクションは未追加
  local adr_file="$GIT_ROOT/$ADR024_PATH"
  run grep -qE "breaking.?change|後方互換|不互換" "$adr_file"
  assert_success
}
