#!/usr/bin/env bats
# su-observer-security-gate.bats - Security gate 節の整合性テスト（W5-1）
#
# Issue #838: su-observer SKILL.md に「Security gate (Layer A-D) 回避は MUST NOT」節を追加
# Issue #984: Security gate 詳細を refs/su-observer-security-gate.md へ移動（#984 split）
#
# 設計選択 (#984): SKILL.md 本体に Security gate 概略 stub を維持し、
# 詳細（Layer A-D table / bypass 禁止手法 / 拒否対応プロトコル）は
# refs/su-observer-security-gate.md へ移動。
# bats の grep 対象を $SKILL_MD から $SECURITY_GATE_REF に変更し全アサーション PASS を維持。
#
# Coverage: unit（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

SKILL_MD=""
SECURITY_GATE_REF=""

setup() {
  common_setup
  SKILL_MD="$REPO_ROOT/skills/su-observer/SKILL.md"
  SECURITY_GATE_REF="$REPO_ROOT/skills/su-observer/refs/su-observer-security-gate.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: Security gate 節が SKILL.md に存在し refs/ へ委譲されている
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Security gate セクションが存在する
# WHEN: su-observer SKILL.md を参照する
# THEN: Security gate セクションが存在し refs/ ファイルへの Read 参照がある
# ---------------------------------------------------------------------------

@test "security-gate: SKILL.md が存在する" {
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"
}

@test "security-gate: Security gate セクションが存在する" {
  grep -q 'Security gate' "$SKILL_MD" \
    || fail "SKILL.md に 'Security gate' セクションが存在しない"
}

@test "security-gate: SKILL.md が refs/su-observer-security-gate.md を参照している" {
  grep -qE "refs/su-observer-security-gate\.md" "$SKILL_MD" \
    || fail "SKILL.md に refs/su-observer-security-gate.md への Read 参照が存在しない（#984 split 確認）"
}

@test "security-gate: refs/su-observer-security-gate.md が存在する" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない: $SECURITY_GATE_REF"
}

# ---------------------------------------------------------------------------
# Scenario: Layer A-D 各 gate が refs/ ファイルに記載される
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: Layer A-D と各 gate 名称が記載されている
# ---------------------------------------------------------------------------

@test "security-gate: Layer A (session-state) が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'Layer A|session.?state' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'Layer A' / 'session-state' が存在しない"
}

@test "security-gate: Layer B (worker-bash) が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'Layer B|worker.?bash' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'Layer B' / 'worker-bash' が存在しない"
}

@test "security-gate: Layer C (git) が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'Layer C|git.*gate|git.*防止' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'Layer C' / 'git gate' が存在しない"
}

@test "security-gate: Layer D (refined-label) が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'Layer D|refined.?label' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'Layer D' / 'refined-label' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 禁止 bypass 手法が refs/ ファイルに明記される
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: 3 つの bypass 手法が MUST NOT として記載されている
# ---------------------------------------------------------------------------

@test "security-gate: session file pre-seed 禁止が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'session file.*pre.?seed|pre.?seed.*session' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'session file pre-seed' 禁止が存在しない"
}

@test "security-gate: inject with bypass hint 禁止が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'bypass hint|inject.*bypass|bypass.*inject' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'inject with bypass hint' 禁止が存在しない"
}

@test "security-gate: settings self-modification 禁止が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'settings.*self.?modif|self.?modif.*settings|settings\.json.*permission' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'settings self-modification' 禁止が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 2 回連続 deny で STOP + AskUserQuestion ルールが記載される
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: 2 回以上 deny → STOP + AskUserQuestion が MUST として明記されている
# ---------------------------------------------------------------------------

@test "security-gate: 2 回以上 deny の STOP ルールが記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE '2.*回.*deny|2.*回.*拒否|deny.*2.*回' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に '2 回以上 deny' ルールが存在しない"
}

@test "security-gate: STOP が MUST として記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'MUST.*STOP|STOP.*MUST|即時.*STOP|STOP.*即時' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'STOP' が MUST として存在しない"
}

@test "security-gate: AskUserQuestion が対応手順に記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -q 'AskUserQuestion' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'AskUserQuestion' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: bypass permission mode はユーザー判断と明記される
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: bypass permission mode の自動提案禁止が記載されている
# ---------------------------------------------------------------------------

@test "security-gate: bypass permission mode 自動提案禁止が記載されている" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'bypass.*mode|bypass permission' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'bypass permission mode' 記述が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §12 と相互参照される
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: pitfalls-catalog §12 への参照が存在する
# ---------------------------------------------------------------------------

@test "security-gate: pitfalls-catalog §12 への参照が存在する" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'pitfalls.catalog.*§12|pitfalls.*§12|pitfalls.*12' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'pitfalls-catalog.md §12' 参照が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: intervention-catalog パターン 13 (W5-2) と整合する
# WHEN: refs/su-observer-security-gate.md を参照する
# THEN: intervention-catalog パターン 13 への参照が存在する
# ---------------------------------------------------------------------------

@test "security-gate: intervention-catalog パターン 13 への参照が存在する" {
  [[ -f "$SECURITY_GATE_REF" ]] \
    || fail "refs/su-observer-security-gate.md が存在しない"
  grep -qiE 'intervention.*13|パターン.*13|pattern.*13' "$SECURITY_GATE_REF" \
    || fail "refs/su-observer-security-gate.md に 'intervention-catalog パターン 13' 参照が存在しない"
}
