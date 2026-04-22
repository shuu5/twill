#!/usr/bin/env bats
# su-observer-security-gate.bats - SKILL.md Security gate 節の整合性テスト（W5-1）
#
# Issue #838: su-observer SKILL.md に「Security gate (Layer A-D) 回避は MUST NOT」節を追加
#
# Coverage: unit（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

SKILL_MD=""

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: Security gate 節が SKILL.md に存在する
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Security gate セクションが存在する
# WHEN: su-observer SKILL.md を参照する
# THEN: Security gate セクションが存在する
# ---------------------------------------------------------------------------

@test "security-gate: SKILL.md が存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"
}

@test "security-gate: Security gate セクションが存在する" {
  grep -q 'Security gate' "$SKILL_MD" \
    || fail "SKILL.md に 'Security gate' セクションが存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: Layer A-D 各 gate が記載される
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: Layer A-D と各 gate 名称が記載されている
# ---------------------------------------------------------------------------

@test "security-gate: Layer A (session-state) が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'Layer A|session.?state' \
    || fail "SKILL.md Security gate 節に 'Layer A' / 'session-state' が存在しない"
}

@test "security-gate: Layer B (worker-bash) が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'Layer B|worker.?bash' \
    || fail "SKILL.md Security gate 節に 'Layer B' / 'worker-bash' が存在しない"
}

@test "security-gate: Layer C (git) が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'Layer C|git.*gate|git.*防止' \
    || fail "SKILL.md Security gate 節に 'Layer C' / 'git gate' が存在しない"
}

@test "security-gate: Layer D (refined-label) が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'Layer D|refined.?label' \
    || fail "SKILL.md Security gate 節に 'Layer D' / 'refined-label' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 禁止 bypass 手法が明記される
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: 3 つの bypass 手法が MUST NOT として記載されている
# ---------------------------------------------------------------------------

@test "security-gate: session file pre-seed 禁止が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'session file.*pre.?seed|pre.?seed.*session' \
    || fail "SKILL.md Security gate 節に 'session file pre-seed' 禁止が存在しない"
}

@test "security-gate: inject with bypass hint 禁止が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'bypass hint|inject.*bypass|bypass.*inject' \
    || fail "SKILL.md Security gate 節に 'inject with bypass hint' 禁止が存在しない"
}

@test "security-gate: settings self-modification 禁止が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'settings.*self.?modif|self.?modif.*settings|settings\.json.*permission' \
    || fail "SKILL.md Security gate 節に 'settings self-modification' 禁止が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 2 回連続 deny で STOP + AskUserQuestion ルールが記載される
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: 2 回以上 deny → STOP + AskUserQuestion が MUST として明記されている
# ---------------------------------------------------------------------------

@test "security-gate: 2 回以上 deny の STOP ルールが記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE '2.*回.*deny|2.*回.*拒否|deny.*2.*回' \
    || fail "SKILL.md Security gate 節に '2 回以上 deny' ルールが存在しない"
}

@test "security-gate: STOP が MUST として記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'MUST.*STOP|STOP.*MUST|即時.*STOP|STOP.*即時' \
    || fail "SKILL.md Security gate 節に 'STOP' が MUST として存在しない"
}

@test "security-gate: AskUserQuestion が対応手順に記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -q 'AskUserQuestion' \
    || fail "SKILL.md Security gate 節に 'AskUserQuestion' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: bypass permission mode はユーザー判断と明記される
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: bypass permission mode の自動提案禁止が記載されている
# ---------------------------------------------------------------------------

@test "security-gate: bypass permission mode 自動提案禁止が記載されている" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'bypass.*mode|bypass permission' \
    || fail "SKILL.md Security gate 節に 'bypass permission mode' 記述が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §12 と相互参照される
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: pitfalls-catalog §12 への参照が存在する
# ---------------------------------------------------------------------------

@test "security-gate: pitfalls-catalog §12 への参照が存在する" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'pitfalls.catalog.*§12|pitfalls.*§12|pitfalls.*12' \
    || fail "SKILL.md Security gate 節に 'pitfalls-catalog.md §12' 参照が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: intervention-catalog パターン 13 (W5-2) と整合する
# WHEN: SKILL.md の Security gate 節を参照する
# THEN: intervention-catalog パターン 13 への参照が存在する
# ---------------------------------------------------------------------------

@test "security-gate: intervention-catalog パターン 13 への参照が存在する" {
  sed -n '/Security gate/,/^## /p' "$SKILL_MD" \
    | grep -qiE 'intervention.*13|パターン.*13|pattern.*13' \
    || fail "SKILL.md Security gate 節に 'intervention-catalog パターン 13' 参照が存在しない"
}
