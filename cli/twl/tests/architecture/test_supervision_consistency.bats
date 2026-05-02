#!/usr/bin/env bats
# test_supervision_consistency.bats - supervision.md の SU-* 範囲表記整合性テスト
#
# Issue: #1261 supervision.md の SU-* 範囲表記ドリフト修正 + regression bats
#
# 検証する仕様:
#   AC1: supervision.md L246 の「SU-1〜SU-7」が「SU-1〜SU-9」に修正されていること
#   AC3: テーブル定義の SU-N 最大値と本文中の「SU-1〜SU-N」表記の N が一致すること
#
# RED フェーズ:
#   AC1 test: 現在 "SU-1〜SU-7" のため "SU-1〜SU-9" を grep すると FAIL
#   AC3 test: 現在 max=9 vs text=7 のため一致チェックが FAIL

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
    SUPERVISION_MD="$REPO_ROOT/plugins/twl/architecture/domain/contexts/supervision.md"
}

# ===========================================================================
# AC1: supervision.md に "SU-1〜SU-9" が含まれること
# RED: 現在は "SU-1〜SU-7" のため FAIL する
# ===========================================================================

@test "ac1: supervision.md に SU-1〜SU-9 が含まれる" {
    # AC: plugins/twl/architecture/domain/contexts/supervision.md L246 の「SU-1〜SU-7」を「SU-1〜SU-9」に修正
    # RED: 実装前（修正前）は "SU-1〜SU-7" のままなので FAIL する
    [[ -f "$SUPERVISION_MD" ]] \
        || skip "supervision.md が見つかりません: $SUPERVISION_MD"

    grep -qF 'SU-1〜SU-9' "$SUPERVISION_MD" \
        || { echo "FAIL: supervision.md に 'SU-1〜SU-9' が見つかりません（現在は 'SU-1〜SU-7' のまま）"; false; }
}

# ===========================================================================
# AC3 (regression fixture): SU-N テーブル最大値と本文 SU-1〜SU-N の N が一致すること
# RED: 現在 max=9 (テーブル) vs text=7 (本文) で FAIL する
# ===========================================================================

@test "ac3: テーブル定義の SU-N 最大値と本文の SU-1〜SU-N の N が一致する" {
    # AC: SU-* 定義行を抽出し、本文中の「SU-1〜SU-N」表記の N が定義最大値と一致することを assert
    # RED: テーブル最大値 SU-9 に対して本文は SU-1〜SU-7 のため FAIL する
    [[ -f "$SUPERVISION_MD" ]] \
        || skip "supervision.md が見つかりません: $SUPERVISION_MD"

    # テーブルから "| SU-N |" パターンで定義されている最大 N を取得
    # 形式: "| SU-8 |" / "| SU-9 |" 等
    local max_defined
    max_defined="$(grep -oP '^\| SU-\K[0-9]+(?= \|)' "$SUPERVISION_MD" \
        | sort -n \
        | tail -1)"

    [[ -n "$max_defined" ]] \
        || { echo "FAIL: テーブルから SU-N 定義が抽出できませんでした"; false; }

    # 本文中の "SU-1〜SU-N" 表記から N を抽出（最後に出現するものを使用）
    local text_max
    text_max="$(grep -oP 'SU-1〜SU-\K[0-9]+' "$SUPERVISION_MD" \
        | sort -n \
        | tail -1)"

    [[ -n "$text_max" ]] \
        || { echo "FAIL: 本文中に 'SU-1〜SU-N' 表記が見つかりませんでした"; false; }

    # 定義最大値と本文の N が一致すること
    [[ "$max_defined" -eq "$text_max" ]] \
        || { echo "FAIL: テーブル最大値 SU-${max_defined} と本文表記 SU-1〜SU-${text_max} が不一致"; false; }
}
