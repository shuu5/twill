#!/usr/bin/env bats
# test_1263_fix_phase_ac_verify.bats
#
# Issue #1263: autopilot が TDD RED-only PR を fix-phase 未実行でマージしてしまうバグ
#
# 対象 AC:
#   AC1: fix-phase.md の発動条件に ac-verify CRITICAL も含めるよう修正
#   AC2: regression fixture —
#        (a) ac-verify CRITICAL 1+ / phase-review CRITICAL 0 → fix-phase が走る
#        (b) 両方 0 → SKIP
#        (c) 両方 1+ → fix-phase が走り両 findings が input として渡る
#   AC3: worker-prompt template に TDD GREEN phase まで実装する旨の指示を追加
#   AC4: pr-merge-chain-steps.md の fix-phase セクションに ac-verify CRITICAL も
#        判定対象と明記 / ADR-022 に変更点を記録
#   AC5: 本 fix 後の autopilot で TDD RED → GREEN 完遂が確認される（プロセス AC）
#
# 全テストは実装前に fail (RED) する。

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../../" && pwd)"
    FIX_PHASE_MD="${REPO_ROOT}/plugins/twl/commands/fix-phase.md"
    PR_MERGE_STEPS_MD="${REPO_ROOT}/plugins/twl/refs/pr-merge-chain-steps.md"
    ADR_022_MD="${REPO_ROOT}/plugins/twl/architecture/decisions/ADR-022-chain-ssot-boundary.md"
    CO_AUTOPILOT_SKILL_MD="${REPO_ROOT}/plugins/twl/skills/co-autopilot/SKILL.md"
}

# ===========================================================================
# AC1: fix-phase.md の発動条件に ac-verify CRITICAL が追加されていること
# RED: 現状 fix-phase.md は phase-review の critical_count のみ参照しており
#      ac-verify CRITICAL を参照していないため FAIL する
# ===========================================================================

@test "ac1: fix-phase.md の発動条件に ac-verify CRITICAL が含まれる" {
    # AC: commands/fix-phase.md の SKIP 条件が
    #     phase_review_critical + ac_verify_critical == 0 になっていること
    # RED: 実装前は ac-verify への言及がないため FAIL する
    [[ -f "$FIX_PHASE_MD" ]] \
        || { echo "FAIL: fix-phase.md が見つかりません: $FIX_PHASE_MD"; false; }

    # ac-verify checkpoint への参照が追加されていること
    grep -qE 'ac.verify' "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に ac-verify への言及がありません"; false; }

    # 発動条件として ac_verify の critical_count / CRITICAL が参照されていること
    grep -qE 'ac.verify.*critical|ac_verify.*CRITICAL|ac_verify_critical|phase_review_critical.*ac_verify' \
        "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md の発動条件に ac_verify CRITICAL が含まれていません"; false; }
}

# ===========================================================================
# AC2-a: ac-verify CRITICAL 1+ / phase-review CRITICAL 0 → fix-phase が走ること
# RED: 現状の fix-phase.md は phase-review CRITICAL のみを参照しているため
#      このシナリオでは fix-phase をスキップしてしまい FAIL する
# ===========================================================================

@test "ac2a: ac-verify CRITICAL 1+ かつ phase-review CRITICAL 0 のとき fix-phase が実行される" {
    # AC: ac-verify.json に CRITICAL findings が存在し phase-review.json に CRITICAL 0 の場合、
    #     fix-phase を SKIP しないこと
    # RED: 実装前の fix-phase.md は phase-review critical_count > 0 のみを条件とするため
    #      このシナリオは SKIP 扱いになり FAIL する

    [[ -f "$FIX_PHASE_MD" ]] \
        || { echo "FAIL: fix-phase.md が見つかりません: $FIX_PHASE_MD"; false; }

    # 修正後は ac-verify CRITICAL 単独でも fix-phase を発動する条件が記載されること
    # 具体的には "phase_review_critical + ac_verify_critical == 0" のみが SKIP 条件
    grep -qE 'ac_verify_critical.*==.*0|ac.verify.*0.*skip|phase_review_critical.*ac_verify_critical' \
        "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に ac_verify_critical == 0 を SKIP 条件とする記述がありません"; false; }
}

# ===========================================================================
# AC2-b: phase-review CRITICAL 0 かつ ac-verify CRITICAL 0 → fix-phase が SKIP
# RED: 上記条件の記述が存在しないため FAIL する（AC1/AC2-a と同起因）
# ===========================================================================

@test "ac2b: phase-review CRITICAL 0 かつ ac-verify CRITICAL 0 のとき fix-phase を SKIP する" {
    # AC: 両方 0 の場合のみ SKIP — SKILL.md またはコマンドに明記されていること
    # RED: 実装前は SKIP 条件が "phase-review critical_count == 0" のみのため FAIL する

    [[ -f "$FIX_PHASE_MD" ]] \
        || { echo "FAIL: fix-phase.md が見つかりません: $FIX_PHASE_MD"; false; }

    # SKIP 条件として "両方 0" であることが明記されていること
    grep -qE 'SKIP|skip' "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に SKIP 条件の記述がありません"; false; }

    # 両方 0 のときのみ SKIP という制約が表現されていること
    grep -qE '(phase_review_critical|phase.review).*\+.*(ac_verify_critical|ac.verify)|両方.*0|both.*0|== 0.*SKIP' \
        "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に phase_review + ac_verify の合計 == 0 を SKIP 条件とする記述がありません"; false; }
}

# ===========================================================================
# AC2-c: 両方 CRITICAL 1+ → fix-phase が両 findings を input として渡す
# RED: ac-verify findings を input に渡すロジックが未実装のため FAIL する
# ===========================================================================

@test "ac2c: phase-review と ac-verify 両方 CRITICAL 1+ のとき両 findings が fix-phase の input として渡される" {
    # AC: fix-phase.md が phase-review と ac-verify の両 checkpoint から
    #     CRITICAL findings を取得して修正指示に渡していること
    # RED: 現在は phase-review checkpoint からのみ取得しており ac-verify を読まない

    [[ -f "$FIX_PHASE_MD" ]] \
        || { echo "FAIL: fix-phase.md が見つかりません: $FIX_PHASE_MD"; false; }

    # ac-verify checkpoint からの findings 取得コマンドが記載されていること
    grep -qE 'checkpoint.*read.*ac.verify|ac.verify.*checkpoint.*read|step ac.verify.*findings|ac.verify.*critical.findings' \
        "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に ac-verify checkpoint からの findings 取得が記載されていません"; false; }
}

# ===========================================================================
# AC3: worker-prompt (co-autopilot SKILL.md) に TDD GREEN phase 完遂の指示が追加されていること
# RED: 現状の co-autopilot SKILL.md に TDD/GREEN/scaffold に関する制約記述がないため FAIL する
# ===========================================================================

@test "ac3: co-autopilot SKILL.md に TDD GREEN phase 完遂の指示が含まれる" {
    # AC: plugins/twl/skills/co-autopilot/SKILL.md または
    #     plugins/twl/scripts/issue-lifecycle-orchestrator.sh の worker prompt 生成箇所に
    #     「TDD-style Issue では GREEN phase まで実装し test scaffold のみで PR を出してはならない」
    #     旨の指示が追加されていること
    # RED: 実装前はこの旨の記述がないため FAIL する

    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # TDD / GREEN / scaffold に関する制約が追加されていること
    grep -qE 'TDD|GREEN.*phase|GREEN.*実装|test.*scaffold.*PR|scaffold.*のみ.*PR.*禁止|RED.*状態.*PR.*禁止' \
        "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: co-autopilot SKILL.md に TDD GREEN phase まで実装する旨の指示がありません"; false; }
}

# ===========================================================================
# AC4-a: pr-merge-chain-steps.md の fix-phase セクションに ac-verify CRITICAL も
#         判定対象と明記されていること
# RED: 現状 pr-merge-chain-steps.md に ac-verify CRITICAL への言及がないため FAIL する
# ===========================================================================

@test "ac4a: pr-merge-chain-steps.md の fix-phase セクションに ac-verify CRITICAL が明記されている" {
    # AC: plugins/twl/refs/pr-merge-chain-steps.md の fix-phase セクションに
    #     「ac-verify CRITICAL も判定対象」と明記されていること
    # RED: 現状この記述がないため FAIL する

    [[ -f "$PR_MERGE_STEPS_MD" ]] \
        || { echo "FAIL: pr-merge-chain-steps.md が見つかりません: $PR_MERGE_STEPS_MD"; false; }

    grep -qE 'ac.verify.*CRITICAL.*判定|ac.verify.*判定.*対象|fix.phase.*ac.verify.*CRITICAL' \
        "$PR_MERGE_STEPS_MD" \
        || { echo "FAIL: pr-merge-chain-steps.md に ac-verify CRITICAL 判定対象の記述がありません"; false; }
}

# ===========================================================================
# AC4-b: ADR-022 に今回の変更点（ac-verify CRITICAL を fix-phase 条件に追加）が記録されていること
# RED: 現状 ADR-022 に Issue #1263 の変更内容が記録されていないため FAIL する
# ===========================================================================

@test "ac4b: ADR-022 に ac-verify CRITICAL を fix-phase 判定に追加した変更点が記録されている" {
    # AC: ADR-022-chain-ssot-boundary.md に #1263 または
    #     ac-verify CRITICAL を fix-phase 条件に追加した旨の記述が追加されていること
    # RED: 実装前は ADR-022 に今回変更の記録がないため FAIL する

    [[ -f "$ADR_022_MD" ]] \
        || { echo "FAIL: ADR-022-chain-ssot-boundary.md が見つかりません: $ADR_022_MD"; false; }

    grep -qE '#1263|ac.verify.*CRITICAL.*fix.phase|fix.phase.*ac.verify.*CRITICAL' \
        "$ADR_022_MD" \
        || { echo "FAIL: ADR-022 に #1263 または ac-verify CRITICAL → fix-phase 変更の記録がありません"; false; }
}

# ===========================================================================
# AC5: プロセス AC（検証）— minimal fixture で TDD RED → GREEN 完遂を機械的に確認
# RED: 本 fix 前は ac-verify CRITICAL があっても fix-phase がスキップされるため
#      RED → GREEN フローが成立しない。fix-phase.md の修正なしでは FAIL する。
# ===========================================================================

@test "ac5: fix-phase.md が ac-verify CRITICAL を含む発動条件を持つ（TDD RED->GREEN 前提条件）" {
    # AC: プロセス AC の前提として fix-phase.md が ac-verify CRITICAL に反応すること。
    #     lab-assistant#6 等の full e2e 検証は本テストスコープ外だが、
    #     その前提条件（fix-phase 修正済み）を機械確認する。
    # RED: 実装前は ac-verify への言及が一切ないため FAIL する

    [[ -f "$FIX_PHASE_MD" ]] \
        || { echo "FAIL: fix-phase.md が見つかりません: $FIX_PHASE_MD"; false; }

    # AC1 と同じ観点を AC5 視点から確認: ac-verify CRITICAL への言及が存在すること
    local ac_verify_mention_count
    ac_verify_mention_count="$(grep -cE 'ac.verify' "$FIX_PHASE_MD" 2>/dev/null || true)"
    ac_verify_mention_count="${ac_verify_mention_count//[^0-9]/}"
    ac_verify_mention_count="${ac_verify_mention_count:-0}"

    # 修正後は ac-verify への言及が 1 行以上あること
    [[ "$ac_verify_mention_count" -gt 0 ]] \
        || { echo "FAIL: fix-phase.md に ac-verify への言及がゼロ行です (count=${ac_verify_mention_count})"; false; }

    # さらに SKIP 条件として ac_verify_critical が含まれること
    grep -qE 'ac_verify_critical|ac.verify.*critical_count' "$FIX_PHASE_MD" \
        || { echo "FAIL: fix-phase.md に ac_verify_critical の SKIP 条件が記述されていません（TDD RED→GREEN 前提条件未達）"; false; }
}
