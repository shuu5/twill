#!/usr/bin/env bats
# pitfalls-catalog-classifier-bypass.bats - pitfalls-catalog §12 存在確認テスト（W6-2）
#
# Issue #828: pitfalls-catalog.md §12 新設 — Claude Code classifier bypass 検出パターン
#
# Coverage: unit（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

PITFALLS_CATALOG=""

setup() {
  common_setup
  PITFALLS_CATALOG="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: pitfalls-catalog §12 classifier bypass 検出パターン
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: §12 セクションが存在する
# WHEN: pitfalls-catalog.md を参照する
# THEN: ## 12. セクションが存在する
# ---------------------------------------------------------------------------

@test "pitfalls §12: ファイルが存在する" {
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"
}

@test "pitfalls §12: §12 セクションが存在する" {
  grep -q '^## 12\.' "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md に '## 12.' セクションが存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 6 連続拒否の具体事例と memory hash 参照が明記される
# WHEN: pitfalls-catalog.md §12 を参照する
# THEN: 6 連続拒否の事例と memory hash 886e374d が記載されている
# ---------------------------------------------------------------------------

@test "pitfalls §12: 6 連続 deny の具体事例が存在する" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qE '6.*連続|6.*deny|6.*拒否' \
    || fail "§12 に '6 連続 deny' の具体事例が存在しない"
}

@test "pitfalls §12: memory hash 886e374d が参照されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -q '886e374d' \
    || fail "§12 に memory hash '886e374d' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 正しい対応手順（STOP + AskUserQuestion）が MUST として記載される
# WHEN: pitfalls-catalog.md §12 を参照する
# THEN: STOP と AskUserQuestion が MUST として明記されている
# ---------------------------------------------------------------------------

@test "pitfalls §12: STOP が MUST として記載されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'MUST.*STOP|STOP.*MUST|即時停止|STOP（即時' \
    || fail "§12 に 'STOP' が MUST として記載されていない"
}

@test "pitfalls §12: AskUserQuestion が対応手順に記載されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -q 'AskUserQuestion' \
    || fail "§12 に 'AskUserQuestion' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: W5-1 (SKILL.md Security gate 節) と相互参照される
# WHEN: pitfalls-catalog.md §12 を参照する
# THEN: W5-1 または SKILL.md Security gate 節への参照が存在する
# ---------------------------------------------------------------------------

@test "pitfalls §12: W5-1 または SKILL.md Security gate 節への参照が存在する" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'W5-1|Security gate|SKILL\.md.*Security' \
    || fail "§12 に 'W5-1' / 'SKILL.md Security gate 節' への参照が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 誤りパターン（bypass 手法）が明記される
# WHEN: pitfalls-catalog.md §12 を参照する
# THEN: session file pre-seed / inject with bypass hint / settings self-modification が記載されている
# ---------------------------------------------------------------------------

@test "pitfalls §12: session file pre-seed パターンが記載されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'session file.*pre.?seed|pre.?seed.*session' \
    || fail "§12 に 'session file pre-seed' パターンが存在しない"
}

@test "pitfalls §12: inject with bypass hint パターンが記載されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'bypass hint|inject.*bypass|bypass.*inject' \
    || fail "§12 に 'inject with bypass hint' パターンが存在しない"
}

@test "pitfalls §12: settings self-modification パターンが記載されている" {
  sed -n '/^## 12\./,/^## [0-9]/p' "$PITFALLS_CATALOG" \
    | grep -qiE 'settings.*self.?modif|self.?modif.*settings|settings\.json.*permission' \
    || fail "§12 に 'settings self-modification' パターンが存在しない"
}
