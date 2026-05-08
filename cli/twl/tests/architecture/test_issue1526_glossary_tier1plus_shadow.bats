#!/usr/bin/env bats
# test_issue1526_glossary_tier1plus_shadow.bats - Tier 1+ / shadow rollout pattern glossary 登録テスト
#
# Issue: #1526 tech-debt: glossary.md に Tier 1+ / shadow rollout pattern 用語を追加
#
# 検証する仕様:
#   AC-1: glossary.md に Tier 1+ が MUST テーブルに登録されていること
#   AC-2: glossary.md に shadow rollout pattern が登録されていること

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
    GLOSSARY_MD="$REPO_ROOT/plugins/twl/architecture/domain/glossary.md"
}

# ===========================================================================
# AC-1: MUST テーブルに "Tier 1+" が登録されていること
# 検証: テーブル行 `| Tier 1+ |` の列境界を含むパターンで用語列限定マッチ
# ===========================================================================

@test "ac1: glossary.md に Tier 1+ が登録されている" {
    # AC: Tier 1+ は ADR-029 Decision 6 で定義された次層改善カテゴリ（observer/controller MCP 化 6 tool 群）
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| Tier 1+ |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| Tier 1+ |' が見つかりません"; false; }
}

# ===========================================================================
# AC-2: MUST テーブルに "shadow rollout pattern" が登録されていること
# 検証: テーブル行 `| shadow rollout pattern |` の列境界を含むパターンで用語列限定マッチ
# ===========================================================================

@test "ac2: glossary.md に shadow rollout pattern が登録されている" {
    # AC: shadow rollout pattern は ADR-029 Decision 5/6 で validated 済の 3-step migration pattern
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| shadow rollout pattern |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| shadow rollout pattern |' が見つかりません"; false; }
}
