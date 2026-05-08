#!/usr/bin/env bats
# ac-scaffold-tests-1578.bats — Issue #1578 AC1/AC4/AC5/AC6/AC7/AC8/AC9/AC10 RED テストスタブ
#
# Issue #1578: feat(supervisor): Issue 起票前 co-explore 強制 enforcement
#
# RED フェーズ: 実装前は全テストが fail する（意図的）
#
# AC カバレッジ:
#   AC1:  ADR-037 ファイル存在 + Status=Proposed + §3.4 構造
#   AC4:  .claude/settings.json に gate hook + mcp_tool 登録
#   AC5:  deps.yaml に pre-bash-issue-create-gate entry 存在 + twl check --deps-integrity PASS
#   AC6:  co-explore Step 1 env marker / co-issue Phase 4 [B] env marker /
#         su-observer MUST NOT 記述 / co-autopilot precondition
#   AC7:  ref-invariants.md に Invariant P 追加（Invariant O の次）
#   AC8:  intervention-catalog.md に SKIP_ISSUE_GATE Layer 1 (Confirm) protocol 追加
#   AC9:  not-testable — プロセス系（retroactive fix）
#   AC10: not-testable — 長期観察系（4 連続 Wave 違反 0 件）

load '../helpers/common'

REPO_ROOT_ABS="/home/shuu5/projects/local-projects/twill/worktrees/feat/1578-featsupervisor-issue-co-explore-enfor"

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ADR-037 起票
# ===========================================================================

# WHEN: ADR-037 ファイルが作成されている
# THEN: Status=Proposed が含まれること
# RED: ファイル未作成のため fail
@test "ac1: ADR-037 ファイルが存在する" {
  # AC1: plugins/twl/architecture/decisions/ADR-037-issue-creation-flow-canonicalization.md 作成
  local adr_path="$REPO_ROOT_ABS/plugins/twl/architecture/decisions/ADR-037-issue-creation-flow-canonicalization.md"
  [ -f "$adr_path" ]  # RED: ファイル未作成
}

@test "ac1: ADR-037 に Status=Proposed が含まれる" {
  local adr_path="$REPO_ROOT_ABS/plugins/twl/architecture/decisions/ADR-037-issue-creation-flow-canonicalization.md"
  [ -f "$adr_path" ] || false  # RED: ファイル未作成

  grep -qF "Proposed" "$adr_path"
}

@test "ac1: ADR-037 に explore-summary §3.4 構造セクションが含まれる" {
  local adr_path="$REPO_ROOT_ABS/plugins/twl/architecture/decisions/ADR-037-issue-creation-flow-canonicalization.md"
  [ -f "$adr_path" ] || false  # RED: ファイル未作成

  # explore-summary §3.4 構造を踏襲: "3.4" または "explore-summary" セクションへの言及
  grep -qE "3\.4|explore-summary" "$adr_path"
}

# ===========================================================================
# AC4: .claude/settings.json PreToolUse Bash hooks 登録
# ===========================================================================

# WHEN: .claude/settings.json に pre-bash-issue-create-gate.sh が登録されている
# THEN: Bash matcher に hook entry が存在すること
# RED: 未登録のため fail
@test "ac4: settings.json の Bash hook に pre-bash-issue-create-gate.sh が登録されている" {
  local settings="$REPO_ROOT_ABS/.claude/settings.json"
  [ -f "$settings" ] || false

  # Bash hook として pre-bash-issue-create-gate が登録されていること
  grep -qF "pre-bash-issue-create-gate" "$settings"  # RED: 未登録
}

# WHEN: .claude/settings.json に mcp_tool validate_issue_create が登録されている
# THEN: outputType: "log" が設定されていること
# RED: 未登録のため fail
@test "ac4: settings.json に twl_validate_issue_create mcp_tool が登録されている (outputType=log)" {
  local settings="$REPO_ROOT_ABS/.claude/settings.json"
  [ -f "$settings" ] || false

  # mcp_tool として validate_issue_create が登録されていること
  grep -qF "validate_issue_create" "$settings"  # RED: 未登録
}

# ===========================================================================
# AC5: deps.yaml scripts セクション + twl check --deps-integrity
# ===========================================================================

# WHEN: deps.yaml に pre-bash-issue-create-gate entry が追加されている
# THEN: scripts セクション内に entry が存在すること
# RED: 未追加のため fail
@test "ac5: deps.yaml に pre-bash-issue-create-gate entry が存在する" {
  local deps_yaml="$REPO_ROOT_ABS/plugins/twl/deps.yaml"
  [ -f "$deps_yaml" ] || false

  # scripts セクションに pre-bash-issue-create-gate エントリが存在すること
  grep -qF "pre-bash-issue-create-gate" "$deps_yaml"  # RED: 未追加
}

# WHEN: deps.yaml の entry が正しい形式で追加されている
# THEN: path エントリが scripts/hooks/pre-bash-issue-create-gate.sh を指すこと
# RED: 未追加のため fail
@test "ac5: deps.yaml の pre-bash-issue-create-gate entry が正しいパスを持つ" {
  local deps_yaml="$REPO_ROOT_ABS/plugins/twl/deps.yaml"
  [ -f "$deps_yaml" ] || false

  grep -qF "scripts/hooks/pre-bash-issue-create-gate.sh" "$deps_yaml"  # RED: 未追加
}

# ===========================================================================
# AC6: 4 controller SKILL.md 修正
# ===========================================================================

# --- AC6a: co-explore Step 1 — env marker + state file 書込み ---

# WHEN: co-explore SKILL.md Step 1 に CO_EXPLORE_DONE env marker の書込みが記述されている
# THEN: SKILL.md に CO_EXPLORE_DONE への言及が存在すること
# RED: 未修正のため fail
@test "ac6a: co-explore SKILL.md Step 1 に CO_EXPLORE_DONE env marker の書込みが記述されている" {
  local skill="$REPO_ROOT_ABS/plugins/twl/skills/co-explore/SKILL.md"
  [ -f "$skill" ] || false

  grep -qF "CO_EXPLORE_DONE" "$skill"  # RED: 未修正
}

# --- AC6b: co-issue Phase 4 [B] path — env marker ---

# WHEN: co-issue SKILL.md Phase 4 [B] path に env marker 設定が記述されている
# THEN: SKILL.md に CO_EXPLORE_DONE または issue-create-gate への言及が存在すること
# RED: 未修正のため fail
@test "ac6b: co-issue SKILL.md Phase 4 [B] path に env marker (CO_EXPLORE_DONE) が記述されている" {
  local skill="$REPO_ROOT_ABS/plugins/twl/skills/co-issue/SKILL.md"
  [ -f "$skill" ] || false

  grep -qF "CO_EXPLORE_DONE" "$skill"  # RED: 未修正
}

# --- AC6c: su-observer SKILL.md — Issue 起票関連 MUST NOT + 不変条件 P 参照 ---

# WHEN: su-observer SKILL.md に Issue 起票関連の MUST NOT が追加されている
# THEN: 不変条件 P または "Issue 起票" に関連する MUST NOT 記述が存在すること
# RED: 未修正のため fail
@test "ac6c: su-observer SKILL.md に Issue 起票関連の MUST NOT が記述されている" {
  local skill="$REPO_ROOT_ABS/plugins/twl/skills/su-observer/SKILL.md"
  [ -f "$skill" ] || false

  # "Issue 起票" かつ "MUST NOT" の両方が含まれるか、
  # または "不変条件 P" への参照が含まれること
  grep -qE "不変条件 P|Invariant P" "$skill"  # RED: 未修正
}

# --- AC6d: co-autopilot SKILL.md — precondition ---

# WHEN: co-autopilot SKILL.md に co-explore 必須の precondition が追加されている
# THEN: SKILL.md に Issue 起票前 co-explore または 不変条件 P への言及が存在すること
# RED: 未修正のため fail
@test "ac6d: co-autopilot SKILL.md に Issue 起票 precondition が記述されている" {
  local skill="$REPO_ROOT_ABS/plugins/twl/skills/co-autopilot/SKILL.md"
  [ -f "$skill" ] || false

  grep -qE "不変条件 P|Invariant P|CO_EXPLORE_DONE|issue-create-gate" "$skill"  # RED: 未修正
}

# ===========================================================================
# AC7: ref-invariants.md に Invariant P 追加
# ===========================================================================

# WHEN: ref-invariants.md に Invariant P (Issue 起票 flow 大原則 SHALL) が追加されている
# THEN: "不変条件 P" または "Invariant P" のセクションが存在すること
# RED: 未追加のため fail
@test "ac7: ref-invariants.md に 不変条件 P が追加されている" {
  local invariants="$REPO_ROOT_ABS/plugins/twl/refs/ref-invariants.md"
  [ -f "$invariants" ] || false

  grep -qE "不変条件 P|## Invariant P" "$invariants"  # RED: 未追加
}

# WHEN: 不変条件 P が ADR-037 を根拠として参照している
# THEN: "ADR-037" への参照が Invariant P セクション内に存在すること
# RED: 未追加のため fail
@test "ac7: ref-invariants.md の 不変条件 P が ADR-037 を根拠として参照している" {
  local invariants="$REPO_ROOT_ABS/plugins/twl/refs/ref-invariants.md"
  [ -f "$invariants" ] || false

  grep -qF "ADR-037" "$invariants"  # RED: 未追加
}

# WHEN: 不変条件 P が 不変条件 O の後に配置されている
# THEN: ファイル内で "不変条件 O" の行より後に "不変条件 P" の行があること
# RED: 未追加のため fail
@test "ac7: ref-invariants.md の 不変条件 P が 不変条件 O の後に配置されている" {
  local invariants="$REPO_ROOT_ABS/plugins/twl/refs/ref-invariants.md"
  [ -f "$invariants" ] || false

  # 不変条件 O と P の両方が存在すること
  grep -qE "不変条件 O" "$invariants" || false
  grep -qE "不変条件 P|Invariant P" "$invariants" || false  # RED: P 未追加

  # P が O より後の行にあること
  local line_o line_p
  line_o=$(grep -n "不変条件 O" "$invariants" | head -1 | cut -d: -f1)
  line_p=$(grep -n "不変条件 P" "$invariants" | head -1 | cut -d: -f1)
  [ -n "$line_p" ] || false  # RED: P が存在しない
  [ "$line_p" -gt "$line_o" ]
}

# ===========================================================================
# AC8: intervention-catalog.md に SKIP_ISSUE_GATE Layer 1 (Confirm) protocol 追加
# ===========================================================================

# WHEN: intervention-catalog.md に SKIP_ISSUE_GATE bypass Layer 1 protocol が追加されている
# THEN: "SKIP_ISSUE_GATE" エントリが存在すること
# RED: 未追加のため fail
@test "ac8: intervention-catalog.md に SKIP_ISSUE_GATE エントリが追加されている" {
  local catalog="$REPO_ROOT_ABS/plugins/twl/refs/intervention-catalog.md"
  [ -f "$catalog" ] || false

  grep -qF "SKIP_ISSUE_GATE" "$catalog"  # RED: 未追加
}

# WHEN: SKIP_ISSUE_GATE が Layer 1 (Confirm) として分類されている
# THEN: "Layer 1" セクション内に SKIP_ISSUE_GATE が存在すること
# RED: 未追加のため fail
@test "ac8: intervention-catalog.md の SKIP_ISSUE_GATE が Layer 1 (Confirm) に分類されている" {
  local catalog="$REPO_ROOT_ABS/plugins/twl/refs/intervention-catalog.md"
  [ -f "$catalog" ] || false

  grep -qF "SKIP_ISSUE_GATE" "$catalog" || false  # RED: 未追加

  # Layer 1 セクション内に SKIP_ISSUE_GATE が含まれること（awk で Layer 1 以降を抽出）
  # Layer 1 の開始行から次の Layer (Layer 2) までの間に SKIP_ISSUE_GATE が存在すること
  awk '/Layer 1: Confirm/,/Layer 2: Escalate/' "$catalog" | grep -qF "SKIP_ISSUE_GATE"  # RED: 未追加
}

# ===========================================================================
# AC9: プロセス系 — not-testable
# ===========================================================================

# not-testable: retroactive fix（#1577 を正規 co-explore flow に戻す +
#   #1554/#1549/#1551 の PR description 明記）はプロセス系であり
#   自動テストの対象外。merge 前には Done にしない AC。
@test "ac9: not-testable — retroactive fix はプロセス系 (記録のみ)" {
  # not-testable: プロセス系 AC のため skip で記録
  skip "AC9 は retroactive fix プロセス。merge 前に Done にしない。su-observer による確認が必要"
}

# ===========================================================================
# AC10: 長期観察系 — not-testable
# ===========================================================================

# not-testable: 4 連続 Wave で gh issue create 違反 0 件（regression 観察）は
#   su-observer による長期集計であり自動テストの対象外。
@test "ac10: not-testable — 4 連続 Wave 違反 0 件は長期観察系 (記録のみ)" {
  # not-testable: 長期観察系 AC のため skip で記録
  skip "AC10 は 4 連続 Wave regression 観察。su-observer による集計。自動テスト対象外"
}
