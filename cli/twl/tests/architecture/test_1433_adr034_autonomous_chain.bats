#!/usr/bin/env bats
# test_1433_adr034_autonomous_chain.bats - ADR-034 自律波連鎖信頼性テスト
#
# Issue: #1433 ADR-034: Autonomous Wave Chain Reliability
#
# 検証する仕様:
#   AC-1:  ADR-034 ファイルが新規作成されている
#   AC-2:  Status: Accepted が記載されている
#   AC-3:  Context に F1/F2/F3 と AUTO_KILL=0 維持制約が明記されている
#   AC-4:  Decision に 5 principles が箇条書きで記載されている
#   AC-5:  Architecture に 4-layer 図（Layer 0-4）が記載されている
#   AC-6:  Consequences に利点・コストが記載されている
#   AC-7:  Alternatives rejected に 3 つの却下案と却下理由が記載されている
#   AC-8:  Risk に 6 項目と mitigation が table 形式で記載されている
#   AC-9:  Related に ADR 相互参照と Epic/Sub-Issues 参照が記載されている
#   AC-10: markdown lint（既存 ADR と同一フォーマット）に準拠している
#   AC-11: Issue タイトルが ADR-034 に更新済みであること（GitHub API 要）
#
# RED フェーズ:
#   全 @test は ADR-034 ファイル未作成のため FAIL する（AC-11 は skip）

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
    ADR034="$REPO_ROOT/plugins/twl/architecture/decisions/ADR-034-autonomous-chain-reliability.md"
}

# ===========================================================================
# AC-1: ADR-034 ファイルが新規作成されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac1: ADR-034 ファイルが存在する" {
    # AC: plugins/twl/architecture/decisions/ADR-034-autonomous-chain-reliability.md が新規作成されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }
}

# ===========================================================================
# AC-2: Status: Accepted が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac2: Status Accepted が記載されている" {
    # AC: Status: Accepted が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'Accepted' "$ADR034" \
        || { echo "FAIL: ADR-034 に 'Accepted' が見つかりません"; false; }
}

# ===========================================================================
# AC-3: Context section に Failure mode F1 が明記されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac3a: Context に Failure mode F1 が明記されている" {
    # AC: Context section に Failure mode F1/F2/F3 と AUTO_KILL=0 維持制約が明記されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'F1' "$ADR034" \
        || { echo "FAIL: ADR-034 の Context に 'F1' が見つかりません"; false; }
}

# ===========================================================================
# AC-3: Context section に Failure mode F2 が明記されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac3b: Context に Failure mode F2 が明記されている" {
    # AC: Context section に Failure mode F1/F2/F3 と AUTO_KILL=0 維持制約が明記されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'F2' "$ADR034" \
        || { echo "FAIL: ADR-034 の Context に 'F2' が見つかりません"; false; }
}

# ===========================================================================
# AC-3: Context section に Failure mode F3 が明記されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac3c: Context に Failure mode F3 が明記されている" {
    # AC: Context section に Failure mode F1/F2/F3 と AUTO_KILL=0 維持制約が明記されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'F3' "$ADR034" \
        || { echo "FAIL: ADR-034 の Context に 'F3' が見つかりません"; false; }
}

# ===========================================================================
# AC-3: Context section に AUTO_KILL=0 維持制約が明記されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac3d: Context に AUTO_KILL=0 維持制約が明記されている" {
    # AC: Context section に Failure mode F1/F2/F3 と AUTO_KILL=0 維持制約が明記されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'AUTO_KILL=0' "$ADR034" \
        || { echo "FAIL: ADR-034 の Context に 'AUTO_KILL=0' が見つかりません"; false; }
}

# ===========================================================================
# AC-4: Decision に LLM judgment exclusion principle が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac4a: Decision に LLM judgment exclusion principle が記載されている" {
    # AC: Decision section に 5 つの principle が箇条書きで記載されている（LLM judgment exclusion）
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'LLM judgment' "$ADR034" \
        || { echo "FAIL: ADR-034 の Decision に 'LLM judgment' が見つかりません"; false; }
}

# ===========================================================================
# AC-4: Decision に Multi-layer signal redundancy principle が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac4b: Decision に Multi-layer signal redundancy principle が記載されている" {
    # AC: Decision section に 5 つの principle が箇条書きで記載されている（Multi-layer signal redundancy）
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'Multi-layer signal redundancy' "$ADR034" \
        || { echo "FAIL: ADR-034 の Decision に 'Multi-layer signal redundancy' が見つかりません"; false; }
}

# ===========================================================================
# AC-4: Decision に Dedicated executor daemon principle が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac4c: Decision に Dedicated executor daemon principle が記載されている" {
    # AC: Decision section に 5 つの principle が箇条書きで記載されている（Dedicated executor daemon）
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'Dedicated executor daemon' "$ADR034" \
        || { echo "FAIL: ADR-034 の Decision に 'Dedicated executor daemon' が見つかりません"; false; }
}

# ===========================================================================
# AC-4: Decision に Observer role redefinition principle が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac4d: Decision に Observer role redefinition principle が記載されている" {
    # AC: Decision section に 5 つの principle が箇条書きで記載されている（Observer role redefinition）
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'Observer role redefinition' "$ADR034" \
        || { echo "FAIL: ADR-034 の Decision に 'Observer role redefinition' が見つかりません"; false; }
}

# ===========================================================================
# AC-4: Decision に Data SSoT enforcement principle が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac4e: Decision に Data SSoT enforcement principle が記載されている" {
    # AC: Decision section に 5 つの principle が箇条書きで記載されている（Data SSoT enforcement）
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'Data SSoT enforcement' "$ADR034" \
        || { echo "FAIL: ADR-034 の Decision に 'Data SSoT enforcement' が見つかりません"; false; }
}

# ===========================================================================
# AC-5: Architecture section に Layer 0 が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac5a: Architecture に Layer 0 が記載されている" {
    # AC: Architecture section に 4-layer 図（Layer 0-4）が ASCII art または table で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE 'Layer 0|Layer0' "$ADR034" \
        || { echo "FAIL: ADR-034 の Architecture に 'Layer 0' が見つかりません"; false; }
}

# ===========================================================================
# AC-5: Architecture section に Layer 4 が記載されている（4-layer 図の範囲確認）
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac5b: Architecture に Layer 4 が記載されている" {
    # AC: Architecture section に 4-layer 図（Layer 0-4）が ASCII art または table で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE 'Layer 4|Layer4' "$ADR034" \
        || { echo "FAIL: ADR-034 の Architecture に 'Layer 4' が見つかりません"; false; }
}

# ===========================================================================
# AC-6: Consequences section に reliability の利点が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac6a: Consequences に reliability の利点が記載されている" {
    # AC: Consequences section に reliability / crash resilience / observability の利点と operational complexity / migration cost のコストが記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'reliability' "$ADR034" \
        || { echo "FAIL: ADR-034 の Consequences に 'reliability' が見つかりません"; false; }
}

# ===========================================================================
# AC-6: Consequences section に crash resilience の利点が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac6b: Consequences に crash resilience の利点が記載されている" {
    # AC: Consequences section に reliability / crash resilience / observability の利点と operational complexity / migration cost のコストが記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'crash resilience' "$ADR034" \
        || { echo "FAIL: ADR-034 の Consequences に 'crash resilience' が見つかりません"; false; }
}

# ===========================================================================
# AC-6: Consequences section に observability の利点が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac6c: Consequences に observability の利点が記載されている" {
    # AC: Consequences section に reliability / crash resilience / observability の利点と operational complexity / migration cost のコストが記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'observability' "$ADR034" \
        || { echo "FAIL: ADR-034 の Consequences に 'observability' が見つかりません"; false; }
}

# ===========================================================================
# AC-6: Consequences section に operational complexity のコストが記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac6d: Consequences に operational complexity のコストが記載されている" {
    # AC: Consequences section に reliability / crash resilience / observability の利点と operational complexity / migration cost のコストが記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'operational complexity' "$ADR034" \
        || { echo "FAIL: ADR-034 の Consequences に 'operational complexity' が見つかりません"; false; }
}

# ===========================================================================
# AC-6: Consequences section に migration cost のコストが記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac6e: Consequences に migration cost のコストが記載されている" {
    # AC: Consequences section に reliability / crash resilience / observability の利点と operational complexity / migration cost のコストが記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'migration cost' "$ADR034" \
        || { echo "FAIL: ADR-034 の Consequences に 'migration cost' が見つかりません"; false; }
}

# ===========================================================================
# AC-7: Alternatives rejected に AUTO_KILL=1 復帰案の却下理由が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac7a: Alternatives に AUTO_KILL=1 復帰案の却下理由が記載されている" {
    # AC: Alternatives rejected section に 3 つの却下案（AUTO_KILL=1 復帰）と却下理由が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'AUTO_KILL=1' "$ADR034" \
        || { echo "FAIL: ADR-034 の Alternatives に 'AUTO_KILL=1' が見つかりません"; false; }
}

# ===========================================================================
# AC-7: Alternatives rejected に cld-observe-any 拡張案の却下理由が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac7b: Alternatives に cld-observe-any 拡張案の却下理由が記載されている" {
    # AC: Alternatives rejected section に 3 つの却下案（cld-observe-any 拡張のみ）と却下理由が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'cld-observe-any' "$ADR034" \
        || { echo "FAIL: ADR-034 の Alternatives に 'cld-observe-any' が見つかりません"; false; }
}

# ===========================================================================
# AC-7: Alternatives rejected に Stop hook のみ案の却下理由が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac7c: Alternatives に Stop hook のみ案の却下理由が記載されている" {
    # AC: Alternatives rejected section に 3 つの却下案（Stop hook のみ）と却下理由が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'Stop hook' "$ADR034" \
        || { echo "FAIL: ADR-034 の Alternatives に 'Stop hook' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk section に table 形式で記載されている（テーブル境界の確認）
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac8a: Risk section に table 形式が存在する" {
    # AC: Risk section に 6 項目と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF '| SPOF |' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に '| SPOF |' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk table に race condition が記載されている
# RED: ファイルが存在しないため FAIL する
# 注意: 用語列限定マッチに '| race condition |' を使用（偽陽性防止）
# ===========================================================================

@test "ac8b: Risk table に race condition が記載されている" {
    # AC: Risk section に race condition と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'race condition' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に 'race condition' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk table に gh API rate limit が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac8c: Risk table に gh API rate limit が記載されている" {
    # AC: Risk section に gh API rate limit と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'rate limit' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に 'rate limit' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk table に event 欠損が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac8d: Risk table に event 欠損が記載されている" {
    # AC: Risk section に event 欠損と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'event' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に 'event' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk table に spawn race が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac8e: Risk table に spawn race が記載されている" {
    # AC: Risk section に spawn race と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qi 'spawn race' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に 'spawn race' が見つかりません"; false; }
}

# ===========================================================================
# AC-8: Risk table に event 蓄積（accumulation）が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac8f: Risk table に event 蓄積が記載されている" {
    # AC: Risk section に event 蓄積と mitigation が table 形式で記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qiE 'event.*(accum|蓄積)|蓄積.*event' "$ADR034" \
        || { echo "FAIL: ADR-034 の Risk table に 'event 蓄積' または 'event accumulation' が見つかりません"; false; }
}

# ===========================================================================
# AC-9: Related section に ADR-013 への相互参照が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac9a: Related に ADR-013 への参照が記載されている" {
    # AC: Related section に ADR-013 / ADR-014 / ADR-029 への相互参照と Epic #1425 / Sub-Issues S1〜S7 への参照が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'ADR-013' "$ADR034" \
        || { echo "FAIL: ADR-034 の Related に 'ADR-013' が見つかりません"; false; }
}

# ===========================================================================
# AC-9: Related section に ADR-014 への相互参照が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac9b: Related に ADR-014 への参照が記載されている" {
    # AC: Related section に ADR-013 / ADR-014 / ADR-029 への相互参照が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'ADR-014' "$ADR034" \
        || { echo "FAIL: ADR-034 の Related に 'ADR-014' が見つかりません"; false; }
}

# ===========================================================================
# AC-9: Related section に ADR-029 への相互参照が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac9c: Related に ADR-029 への参照が記載されている" {
    # AC: Related section に ADR-013 / ADR-014 / ADR-029 への相互参照が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF 'ADR-029' "$ADR034" \
        || { echo "FAIL: ADR-034 の Related に 'ADR-029' が見つかりません"; false; }
}

# ===========================================================================
# AC-9: Related section に Epic #1425 への参照が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac9d: Related に Epic #1425 への参照が記載されている" {
    # AC: Related section に Epic #1425 / Sub-Issues S1〜S7 への参照が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qF '1425' "$ADR034" \
        || { echo "FAIL: ADR-034 の Related に '1425' が見つかりません"; false; }
}

# ===========================================================================
# AC-9: Related section に Sub-Issues S1〜S7 への参照が記載されている
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac9e: Related に Sub-Issues S1〜S7 への参照が記載されている" {
    # AC: Related section に Sub-Issues S1〜S7 への参照が記載されている
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE 'S[1-7]' "$ADR034" \
        || { echo "FAIL: ADR-034 の Related に 'S1〜S7' のいずれかが見つかりません"; false; }
}

# ===========================================================================
# AC-10: markdown lint - H1 見出しが ADR-034 で始まる
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac10a: markdown lint - H1 見出しが ADR-034 で始まる" {
    # AC: markdown lint（既存 ADR と同一フォーマット）に準拠している
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE '^# ADR-034' "$ADR034" \
        || { echo "FAIL: ADR-034 の H1 見出しが '# ADR-034' で始まっていません"; false; }
}

# ===========================================================================
# AC-10: markdown lint - ## Status セクションが存在する
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac10b: markdown lint - Status セクションが存在する" {
    # AC: markdown lint（既存 ADR と同一フォーマット）に準拠している
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE '^## Status' "$ADR034" \
        || { echo "FAIL: ADR-034 に '## Status' セクションが見つかりません"; false; }
}

# ===========================================================================
# AC-10: markdown lint - ## Context セクションが存在する
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac10c: markdown lint - Context セクションが存在する" {
    # AC: markdown lint（既存 ADR と同一フォーマット）に準拠している
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE '^## Context' "$ADR034" \
        || { echo "FAIL: ADR-034 に '## Context' セクションが見つかりません"; false; }
}

# ===========================================================================
# AC-10: markdown lint - ## Decision セクションが存在する
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac10d: markdown lint - Decision セクションが存在する" {
    # AC: markdown lint（既存 ADR と同一フォーマット）に準拠している
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE '^## Decision' "$ADR034" \
        || { echo "FAIL: ADR-034 に '## Decision' セクションが見つかりません"; false; }
}

# ===========================================================================
# AC-10: markdown lint - ## Consequences セクションが存在する
# RED: ファイルが存在しないため FAIL する
# ===========================================================================

@test "ac10e: markdown lint - Consequences セクションが存在する" {
    # AC: markdown lint（既存 ADR と同一フォーマット）に準拠している
    # RED: 実装前はファイルが存在しないため FAIL する
    [[ -f "$ADR034" ]] \
        || { echo "FAIL: ADR-034 ファイルが見つかりません: $ADR034"; false; }

    grep -qE '^## Consequences' "$ADR034" \
        || { echo "FAIL: ADR-034 に '## Consequences' セクションが見つかりません"; false; }
}

# ===========================================================================
# AC-11: Issue タイトルが ADR-034 に更新済みであること
# GitHub API が必要なため skip する
# ===========================================================================

@test "ac11: Issue タイトルが ADR-034 に更新済みである" {
    # AC: Issue タイトルを ADR-030 から ADR-034 に更新済みであること
    # GitHub API が必要なため skip
    skip "AC-11: GitHub API による Issue タイトル確認は自動化対象外（手動確認）"
}
