#!/usr/bin/env bats
# test_1317_auto_default_interactive.bats
#
# Issue #1317: feat(co-autopilot): --auto を default 化 + --interactive flag 追加
#
# 対象 AC:
#   AC-1: co-autopilot/SKILL.md Step 2 default mode = AUTO (skip Plan 承認 menu)
#   AC-2: --interactive flag で従来動作 (Plan 承認 menu 表示)
#   AC-3: regression bats: --auto default 経路で Phase 1 dispatch 直行確認
#   AC-4: spawn-controller.sh で --interactive flag 透過
#
# 全テストは実装前に fail (RED) する。

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../../" && pwd)"
    CO_AUTOPILOT_SKILL_MD="${REPO_ROOT}/plugins/twl/skills/co-autopilot/SKILL.md"
    SPAWN_CONTROLLER_SH="${REPO_ROOT}/plugins/twl/skills/su-observer/scripts/spawn-controller.sh"
}

# ===========================================================================
# AC-1: co-autopilot/SKILL.md Step 2 default mode = AUTO
# RED: 現状 Step 2 に「★HUMAN GATE — 通常モードでは AskUserQuestion」があり
#      default が AUTO ではないため FAIL する
# ===========================================================================

@test "ac1: SKILL.md Step 2 に '--interactive なし' が default AUTO の記述がある" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は Step 2 の default が AUTO であることが明記されていること
    # RED: 現状 "★HUMAN GATE — 通常モードでは AskUserQuestion" が存在し
    #      "--interactive" や "default.*AUTO" の記述がないため FAIL する
    grep -qE 'default.*AUTO|AUTO.*default|デフォルト.*AUTO|AUTO.*デフォルト' "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: SKILL.md Step 2 に default = AUTO の記述がありません"; false; }
}

@test "ac1: SKILL.md Step 2 の HUMAN GATE が --interactive 条件付きになっている" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は HUMAN GATE が --interactive フラグ付き時のみ発動すること
    # RED: 現状 "★HUMAN GATE — 通常モードでは AskUserQuestion" が
    #      無条件に Plan 承認 menu を要求するため FAIL する
    grep -qE 'HUMAN GATE.*interactive|interactive.*HUMAN GATE|interactive.*のみ.*AskUserQuestion|--interactive.*Plan承認|--interactive.*plan.*menu' \
        "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: SKILL.md の HUMAN GATE が --interactive 条件付きになっていません"; false; }
}

# ===========================================================================
# AC-2: --interactive flag で従来動作 (Plan 承認 menu 表示)
# RED: 現状 SKILL.md に --interactive フラグへの言及がないため FAIL する
# ===========================================================================

@test "ac2: SKILL.md に --interactive flag の説明がある" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は --interactive フラグが SKILL.md に明記されていること
    # RED: 現状 --interactive への言及が一切ないため FAIL する
    grep -qE '\-\-interactive' "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: SKILL.md に --interactive フラグの記述がありません"; false; }
}

@test "ac2: SKILL.md の --interactive flag が AskUserQuestion 表示と紐づいている" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は --interactive 時に AskUserQuestion (Plan 承認 menu) が発動する記述があること
    # RED: --interactive の言及自体がないため FAIL する
    grep -qE 'interactive.*AskUserQuestion|interactive.*Plan.*承認|interactive.*plan.*menu|interactive.*承認.*menu' \
        "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: SKILL.md に --interactive → AskUserQuestion の紐づけがありません"; false; }
}

# ===========================================================================
# AC-3: regression bats — --auto default 経路で Phase 1 dispatch 直行確認
# RED: 現状 Step 2 は「通常モードでは AskUserQuestion」であり
#      --interactive なしでの直行が保証されていないため FAIL する
# ===========================================================================

@test "ac3: SKILL.md Step 2 が '--interactive なし' を default AUTO 経路（Phase 1 直行）として明示している" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は "デフォルト（--interactive なし）→ 自動承認（AskUserQuestion 不要）" の記述があること
    # RED: 現状 "--interactive" フラグ自体が存在せず、デフォルトが対話確認モードであるため
    #      "--interactive なし" を明示した直行経路の記述が存在しないため FAIL する
    grep -qE '\-\-interactive.*なし|interactive.*省略.*自動承認|interactive.*省略.*Phase|省略.*interactive.*直行|interactive.*opt.in|opt.in.*interactive' \
        "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: SKILL.md に '--interactive なし → Phase 1 直行' の記述がありません"; false; }
}

@test "ac3: SKILL.md Step 2 に '通常モードでは AskUserQuestion' の無条件記述が存在しない" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    # 実装後は「通常モードでは AskUserQuestion」（--interactive フラグなしの無条件 HUMAN GATE）が
    # 削除されていること
    # RED: 現状この記述が残っているため FAIL する（grep が マッチして false になる）
    if grep -qE '通常モードでは AskUserQuestion|通常時.*AskUserQuestion' "$CO_AUTOPILOT_SKILL_MD"; then
        echo "FAIL: SKILL.md Step 2 に '通常モードでは AskUserQuestion' の無条件記述が残っています（--interactive opt-in 化が未実装）"
        false
    fi
}

# ===========================================================================
# AC-4: spawn-controller.sh で --interactive flag 透過
# RED: 現状 spawn-controller.sh に --interactive の parse ロジックがないため FAIL する
# ===========================================================================

@test "ac4: spawn-controller.sh が --interactive フラグを受け付ける" {
    [[ -f "$SPAWN_CONTROLLER_SH" ]] \
        || { echo "FAIL: spawn-controller.sh が見つかりません: $SPAWN_CONTROLLER_SH"; false; }

    # 実装後は --interactive フラグの parse ロジックが存在すること
    # RED: 現状 spawn-controller.sh に --interactive の parse が存在しないため FAIL する
    grep -qE '\-\-interactive' "$SPAWN_CONTROLLER_SH" \
        || { echo "FAIL: spawn-controller.sh に --interactive フラグのハンドリングがありません"; false; }
}

@test "ac4: spawn-controller.sh が --interactive を co-autopilot へ透過させる記述がある" {
    [[ -f "$SPAWN_CONTROLLER_SH" ]] \
        || { echo "FAIL: spawn-controller.sh が見つかりません: $SPAWN_CONTROLLER_SH"; false; }

    # 実装後は --interactive フラグを受け取り、prompt または cld-spawn 引数として透過させること
    # RED: --interactive の言及自体がないため FAIL する
    grep -qE 'INTERACTIVE|interactive.*flag|interactive.*pass|interactive.*透過|interactive.*forward' \
        "$SPAWN_CONTROLLER_SH" \
        || { echo "FAIL: spawn-controller.sh に --interactive フラグの透過ロジックがありません"; false; }
}
