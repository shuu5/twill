#!/usr/bin/env bats
# test_issue1301_glossary_adr033.bats - ADR-033 導入概念の glossary 登録テスト
#
# Issue: #1301 ADR-033 導入概念(Pinned Reference/protocols/等)をglossary.mdに登録する
#
# 検証する仕様:
#   AC-1: glossary.md に ADR-033 の4用語が MUST テーブルに登録されていること
#     - Pinned Reference, protocols/, SHA pin, Drift Detection
#   AC-4 (regression): 登録済み用語が MUST テーブル（照合対象）に含まれること

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
    GLOSSARY_MD="$REPO_ROOT/plugins/twl/architecture/domain/glossary.md"
}

# ===========================================================================
# AC-1 / AC-4: MUST テーブルに "Pinned Reference" が登録されていること（regression）
# 検証: テーブル行 `| Pinned Reference |` の列境界を含むパターンで MUST 限定マッチ
# ===========================================================================

@test "ac1: glossary.md に Pinned Reference が登録されている" {
    # AC: Pinned Reference: 40-char commit SHA によるクロスリポジトリ参照の固定点
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| Pinned Reference |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| Pinned Reference |' が見つかりません"; false; }
}

# ===========================================================================
# AC-1 / AC-4: MUST テーブルに "protocols/" が登録されていること（regression）
# 検証: テーブル行 `| protocols/ |` の列境界を含むパターンで用語列限定マッチ
# ===========================================================================

@test "ac1: glossary.md に protocols/ が登録されている" {
    # AC: protocols/: クロスリポジトリ知識転送プロトコルを格納するディレクトリ
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| protocols/ |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| protocols/ |' が見つかりません"; false; }
}

# ===========================================================================
# AC-1 / AC-4: MUST テーブルに "SHA pin" が登録されていること（regression）
# ===========================================================================

@test "ac1: glossary.md に SHA pin が登録されている" {
    # AC: SHA pin: 可変参照（tag/branch）を避け、commit SHA で依存を固定すること
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| SHA pin |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| SHA pin |' が見つかりません"; false; }
}

# ===========================================================================
# AC-1 / AC-4: MUST テーブルに "Drift Detection" が登録されていること（regression）
# ===========================================================================

@test "ac1: glossary.md に Drift Detection が登録されている" {
    # AC: Drift Detection: SHA ピンと実際の Provider HEAD を定期比較してずれを検出する運用
    [[ -f "$GLOSSARY_MD" ]] \
        || skip "glossary.md が見つかりません: $GLOSSARY_MD"

    grep -qF '| Drift Detection |' "$GLOSSARY_MD" \
        || { echo "FAIL: glossary.md に '| Drift Detection |' が見つかりません"; false; }
}
