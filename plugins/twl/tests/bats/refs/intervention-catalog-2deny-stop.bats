#!/usr/bin/env bats
# intervention-catalog-2deny-stop.bats - intervention-catalog パターン13 2-deny STOP rule 整合性テスト
#
# Issue #839: intervention-catalog.md に「permission 拒否 2 回以上で STOP + AskUserQuestion」escalation rule 追加
#
# Coverage: unit（ドキュメント内容の機械的固定テスト）

load '../helpers/common'

INTERVENTION_CATALOG=""

setup() {
  common_setup
  INTERVENTION_CATALOG="$REPO_ROOT/refs/intervention-catalog.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: intervention-catalog.md パターン13 2-deny STOP rule
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: ファイルが存在し frontmatter が正しい
# WHEN: intervention-catalog.md を参照する
# THEN: ファイルが存在し type=reference frontmatter を持つ
# ---------------------------------------------------------------------------

@test "intervention-catalog: ファイルが存在する" {
  [[ -f "$INTERVENTION_CATALOG" ]] \
    || fail "intervention-catalog.md が存在しない: $INTERVENTION_CATALOG"
}

@test "intervention-catalog: type=reference frontmatter を持つ" {
  grep -q 'type: reference' "$INTERVENTION_CATALOG" \
    || fail "intervention-catalog.md に 'type: reference' frontmatter がない"
}

# ---------------------------------------------------------------------------
# Scenario: パターン13 が Layer 2 Escalate セクション内に存在する
# WHEN: intervention-catalog.md の Layer 2 Escalate セクションを参照する
# THEN: パターン13 が Layer 2 Escalate の中に配置されている
# ---------------------------------------------------------------------------

@test "intervention-catalog パターン13: Layer 2 Escalate セクションが存在する" {
  grep -q '## Layer 2: Escalate' "$INTERVENTION_CATALOG" \
    || fail "intervention-catalog.md に '## Layer 2: Escalate' セクションがない"
}

@test "intervention-catalog パターン13: パターン13 エントリが存在する" {
  grep -qE '### パターン 13:' "$INTERVENTION_CATALOG" \
    || fail "intervention-catalog.md に 'パターン 13' エントリがない"
}

@test "intervention-catalog パターン13: Layer 2 Escalate 配下に配置されている" {
  # Layer 2 セクション以降にパターン13 が存在することを確認
  sed -n '/^## Layer 2: Escalate/,/^---$/p' "$INTERVENTION_CATALOG" \
    | grep -qE 'パターン 13' \
    || fail "パターン13 が Layer 2 Escalate セクション内に存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 2-deny STOP ルールが明記される
# WHEN: intervention-catalog.md パターン13 を参照する
# THEN: 2 回以上の permission deny で即時 STOP するルールが記載されている
# ---------------------------------------------------------------------------

@test "intervention-catalog パターン13: permission deny 2 回以上の検出条件が記載されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -qE '2 回|2回' \
    || fail "パターン13 に 'permission deny 2 回以上' の検出条件がない"
}

@test "intervention-catalog パターン13: 即時 STOP ルールが記載されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -qiE 'STOP|即時停止' \
    || fail "パターン13 に '即時 STOP' ルールがない"
}

@test "intervention-catalog パターン13: AskUserQuestion が対応手順に記載されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -q 'AskUserQuestion' \
    || fail "パターン13 に 'AskUserQuestion' が存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: W5-1 連携（同一カテゴリ限定）が明記される
# WHEN: intervention-catalog.md パターン13 を参照する
# THEN: W5 連携と同一カテゴリ操作への counter 適用が記載されている
# ---------------------------------------------------------------------------

@test "intervention-catalog パターン13: W5 連携が明記されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -qiE 'W5|Wave 5' \
    || fail "パターン13 に 'W5 連携' が明記されていない"
}

@test "intervention-catalog パターン13: 同一カテゴリ操作の counter 対象が記載されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -qE '同一カテゴリ|same.*categor' \
    || fail "パターン13 に '同一カテゴリ' の counter 対象限定が記載されていない"
}

# ---------------------------------------------------------------------------
# Scenario: Supervisor も 2 回目以降は実行しない制約が記載される
# WHEN: intervention-catalog.md パターン13 を参照する
# THEN: 実行制約として Supervisor も停止することが明記されている
# ---------------------------------------------------------------------------

@test "intervention-catalog パターン13: 実行制約（Supervisor も実行しない）が記載されている" {
  sed -n '/### パターン 13:/,/### パターン/p' "$INTERVENTION_CATALOG" \
    | grep -qiE 'Supervisor.*実行しない|実行制約' \
    || fail "パターン13 に '実行制約: Supervisor も実行しない' が記載されていない"
}
