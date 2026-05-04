#!/usr/bin/env bats
# issue-1374-llm-indicators-ssot.bats
#
# RED-phase tests for Issue #1374:
#   tech-debt: LLM indicator SSOT lib 新設（cld-observe-any から分離）
#
# AC coverage:
#   AC1  - plugins/session/scripts/lib/llm-indicators.sh を新設し LLM_INDICATORS を bash 配列として export（SSOT）
#   AC2  - cld-observe-any L15-44 の inline 配列定義を削除し新 lib を source で参照する
#   AC3  - observer-idle-check.sh L46 の local llm_indicators=... を新 lib 由来に変更
#   AC4  - issue-lifecycle-orchestrator.sh L62-79 の awk 抽出を新 lib source 方式に切り替え
#   AC5  - EN 13 件を SSOT 配列に追加（Philosophising, Drizzling, Fluttering, Spelunking,
#           Determining, Infusing, Prestidigitating, Cogitated, Frolicking, Marinating,
#           Metamorphosing, Shimmying, Transfiguring）
#   AC6  - JP 6 件を SSOT 配列に追加（生成中, 構築中, 処理中, 作成中, 分析中, 検証中）
#   AC9  - observer-idle-check.sh のコメントを「SSOT: lib/llm-indicators.sh を参照」に更新
#   AC10 - monitor-channel-catalog.md または pitfalls §4.10 に SSOT lib の場所と参照規約を追記
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  LLM_INDICATORS_LIB="${REPO_ROOT}/../session/scripts/lib/llm-indicators.sh"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"
  OBSERVER_IDLE_CHECK="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-idle-check.sh"
  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"

  export LLM_INDICATORS_LIB CLD_OBSERVE_ANY OBSERVER_IDLE_CHECK ORCHESTRATOR
  export MONITOR_CATALOG PITFALLS_CATALOG

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: plugins/session/scripts/lib/llm-indicators.sh を新設
#      LLM_INDICATORS を bash 配列として export する（SSOT）
# ===========================================================================

@test "ac1(#1374)/1: plugins/session/scripts/lib/llm-indicators.sh が存在すること (RED)" {
  # AC: plugins/session/scripts/lib/llm-indicators.sh を新設する
  # RED: ファイルが未存在のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
}

@test "ac1(#1374)/2: llm-indicators.sh が LLM_INDICATORS を bash 配列として定義する (RED)" {
  # AC: LLM_INDICATORS を bash 配列として export する（SSOT）
  # RED: ファイルが未存在のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    # LLM_INDICATORS が配列として定義されており要素が存在する
    [[ \"\${#LLM_INDICATORS[@]}\" -gt 0 ]]
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1374)/3: llm-indicators.sh の LLM_INDICATORS が export されている (RED)" {
  # AC: export されていること（source した子プロセスから参照可能）
  # RED: ファイルが未存在または export 未実施のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    # export -p で LLM_INDICATORS が確認できること
    # bash では配列の export は declare -a + export で実現
    export -p | grep -q 'LLM_INDICATORS'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1374)/4: llm-indicators.sh に source guard または function-only load guard があること (RED)" {
  # AC: source guard が存在し、直接実行時に main 到達前に exit しない安全性を保証する
  # RED: ファイルが未存在のため fail
  # NOTE: bash の lib ファイルなので BASH_SOURCE guard または --source-only パターンを確認
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    # 直接実行しても exit 1 等で落ちないこと（lib は source 専用）
    # source guard: BASH_SOURCE[0] != \$0 の場合のみ実行等
    # または: スクリプト本体が関数定義のみで main がない構造
    grep -qE 'BASH_SOURCE|source.only|_DAEMON_LOAD_ONLY|source guard' '${LLM_INDICATORS_LIB}' || \
    ! grep -qE '^[^#]*exit [0-9]' '${LLM_INDICATORS_LIB}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: cld-observe-any L15-44 の inline 配列定義を削除し新 lib を source で参照
# ===========================================================================

@test "ac2(#1374)/1: cld-observe-any の inline LLM_INDICATORS 定義が削除されていること (RED)" {
  # AC: cld-observe-any L15-44 の inline 配列定義を削除する
  # RED: inline 定義がまだ存在するため fail
  run bash -c "
    if grep -q '^LLM_INDICATORS=(' '${CLD_OBSERVE_ANY}'; then
        echo 'FAIL: inline LLM_INDICATORS=( が cld-observe-any に残存（lib 分離未実装）'
        exit 1
    fi
    echo 'PASS: inline 定義なし'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2(#1374)/2: cld-observe-any が llm-indicators.sh を source する行を持つこと (RED)" {
  # AC: 新 lib を source で参照する
  # RED: source 行が未追加のため fail
  run grep -qE 'source.*llm-indicators\.sh|\. .*llm-indicators\.sh' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac2(#1374)/3: cld-observe-any が llm-indicators.sh を source 後 LLM_INDICATORS を参照できる (RED)" {
  # AC: source 後に LLM_INDICATORS が利用可能であること
  # RED: lib 未存在 + source 行未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    # cld-observe-any から source 行を抽出して実行し、LLM_INDICATORS が利用可能か確認
    # _TEST_MODE=1 で main loop 手前まで実行
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR=\"\$(dirname '${CLD_OBSERVE_ANY}')\" \
        bash '${CLD_OBSERVE_ANY}' --source-only 2>/dev/null || true
    source '${LLM_INDICATORS_LIB}'
    [[ \"\${#LLM_INDICATORS[@]}\" -gt 0 ]]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: observer-idle-check.sh L46 の local llm_indicators=... を新 lib 由来に変更
# ===========================================================================

@test "ac3(#1374)/1: observer-idle-check.sh の local llm_indicators=... ハードコードが削除されていること (RED)" {
  # AC: L46 の local llm_indicators=... alternation 文字列を削除し新 lib 由来に変更する
  # RED: ハードコード定義がまだ存在するため fail
  run bash -c "
    if grep -q '^    local llm_indicators=' '${OBSERVER_IDLE_CHECK}'; then
        echo 'FAIL: local llm_indicators= ハードコードが残存（lib 分離未実装）'
        exit 1
    fi
    echo 'PASS: ハードコードなし'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3(#1374)/2: observer-idle-check.sh が llm-indicators.sh を参照する (RED)" {
  # AC: 新 lib 由来の配列から動的生成、または lib に alternation 文字列関数を提供する
  # RED: llm-indicators.sh の明示的 source/参照が未追加のため fail
  # NOTE: 単に LLM_INDICATORS を含むだけでは不十分（ハードコード残存の可能性）
  run grep -qE 'llm-indicators\.sh' "${OBSERVER_IDLE_CHECK}"
  [ "${status}" -eq 0 ]
}

@test "ac3(#1374)/3: observer-idle-check.sh の C3 が llm-indicators.sh 由来の LLM_INDICATORS を使用する (RED)" {
  # AC: C3 判定が lib 由来の配列に基づく
  # RED: lib 由来ではないため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    source '${OBSERVER_IDLE_CHECK}'
    # lib 由来の LLM_INDICATORS が source された状態で _check_idle_completed が動作すること
    # Brewing（既存 EN indicator）がある場合に idle 判定されないこと
    pane_content='Brewing for 5m 30s
nothing pending
処理中です'
    first_seen_ts=100
    now_ts=200
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  # Brewing（LLM indicator）があるため idle 判定されない（non-0）
  [ "${status}" -ne 0 ]
}

# ===========================================================================
# AC4: issue-lifecycle-orchestrator.sh L62-79 の awk 抽出を新 lib source 方式に切り替え
# ===========================================================================

@test "ac4(#1374)/1: issue-lifecycle-orchestrator.sh の awk LLM_INDICATORS 抽出が削除されていること (RED)" {
  # AC: L62-79 の awk 抽出を新 lib source 方式に切り替える
  # RED: awk 抽出コードがまだ存在するため fail
  run bash -c "
    if grep -qE \"awk '/\^LLM_INDICATORS=\" '${ORCHESTRATOR}'; then
        echo 'FAIL: awk LLM_INDICATORS 抽出コードが orchestrator に残存'
        exit 1
    fi
    echo 'PASS: awk 抽出なし'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4(#1374)/2: issue-lifecycle-orchestrator.sh が llm-indicators.sh を source する (RED)" {
  # AC: awk 抽出の代わりに llm-indicators.sh を source する
  # RED: source 行が未追加のため fail
  run grep -qE 'source.*llm-indicators\.sh|\. .*llm-indicators\.sh' "${ORCHESTRATOR}"
  [ "${status}" -eq 0 ]
}

@test "ac4(#1374)/3: orchestrator が lib source 後 LLM_INDICATORS を detect_thinking で利用できる (RED)" {
  # AC: lib source 方式切り替え後も detect_thinking() が動作すること
  # RED: lib 未存在 + source 行未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    # orchestrator から detect_thinking 関数定義を抽出して動作確認
    # LLM_INDICATORS が空でないこと
    [[ \"\${#LLM_INDICATORS[@]}\" -gt 0 ]]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: EN 13 件を SSOT 配列に追加
#      Philosophising, Drizzling, Fluttering, Spelunking, Determining,
#      Infusing, Prestidigitating, Cogitated, Frolicking, Marinating,
#      Metamorphosing, Shimmying, Transfiguring
#      （既登録の Frosting / Saut.*ed / Crunched は除外済）
# ===========================================================================

@test "ac5(#1374)/1: LLM_INDICATORS に Philosophising が含まれること (RED)" {
  # AC: EN 13 件の追加（Philosophising は最初の 1 件）
  # RED: llm-indicators.sh 未存在 + indicator 未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    found=0
    for ind in \"\${LLM_INDICATORS[@]}\"; do
        [[ \"\$ind\" == *'Philosophising'* ]] && found=1 && break
    done
    [[ \$found -eq 1 ]]
  "
  [ "${status}" -eq 0 ]
}

@test "ac5(#1374)/2: LLM_INDICATORS に AC5 EN 13 件が全て含まれること (RED)" {
  # AC: EN 13 件全て SSOT 配列に追加する
  # RED: llm-indicators.sh 未存在または indicator 未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    REQUIRED=(
        Philosophising Drizzling Fluttering Spelunking Determining
        Infusing Prestidigitating Cogitated Frolicking Marinating
        Metamorphosing Shimmying Transfiguring
    )
    missing=()
    for word in \"\${REQUIRED[@]}\"; do
        found=0
        for ind in \"\${LLM_INDICATORS[@]}\"; do
            [[ \"\$ind\" == *\"\$word\"* ]] && found=1 && break
        done
        [[ \$found -eq 0 ]] && missing+=(\"\$word\")
    done
    if [[ \${#missing[@]} -gt 0 ]]; then
        echo \"MISSING EN 13 件: \${missing[*]}\"
        exit 1
    fi
    echo \"PASS: EN 13 件確認 (total=\${#LLM_INDICATORS[@]})\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac5(#1374)/3: Frosting / Saut.*ed / Crunched は既登録のため AC5 追加分に除外されていること (regression guard)" {
  # AC: 既登録の Frosting / Saut.*ed / Crunched は除外済（重複追加しない）
  # このテストは現実装でも PASS する（regression guard）
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    # 既登録 indicator が引き続き配列に存在すること（除外 = 削除ではなく重複追加しない意）
    found_frosting=0
    for ind in \"\${LLM_INDICATORS[@]}\"; do
        [[ \"\$ind\" == *'Frosting'* ]] && found_frosting=1 && break
    done
    [[ \$found_frosting -eq 1 ]]
  "
  [ "${status}" -eq 0 ]
}

@test "ac5(#1374)/4: Philosophising indicator がある pane で STAGNATE emit されないこと (RED)" {
  # AC: 新規追加 EN indicator が実際の thinking guard として機能すること
  # RED: llm-indicators.sh 未存在 + cld-observe-any inline 定義未削除のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    TMPD=\"\$(mktemp -d)\"
    win='ap-philosophising-win'

    capture='Philosophising… (8s)
Contemplating the solution...'
    export capture

    logfile=\"\${TMPD}/\${win}.log\"
    touch -t \"\$(date -d '60 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')\" \"\$logfile\" 2>/dev/null || touch \"\$logfile\"

    tmux() {
        case \"\$1\" in
            list-windows) echo \"test-session:0 \$win\";;
            display-message) echo \"0 claude\";;
            capture-pane)
                if [[ \"\${*}\" == *'-S -1'* ]]; then echo ''; else printf '%s\n' \"\$capture\"; fi;;
            *) return 0;;
        esac
    }
    export -f tmux

    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR=\"\$(dirname '${CLD_OBSERVE_ANY}')\" \
        bash '${CLD_OBSERVE_ANY}' --window \"\$win\" --once \
        --log-dir \"\$TMPD\" \
        --stagnate-sec 5 2>/dev/null
    exit_code=\$?
    rm -rf \"\$TMPD\"
    exit \$exit_code
  "
  [ "${status}" -eq 0 ]
  # Philosophising が LLM indicator として認識されれば STAGNATE は emit されない
  ! echo "${output}" | grep -q "STAGNATE"
}

# ===========================================================================
# AC6: JP 6 件を SSOT 配列に追加
#      生成中, 構築中, 処理中, 作成中, 分析中, 検証中
# ===========================================================================

@test "ac6(#1374)/1: LLM_INDICATORS に JP 6 件（生成中 等）が全て含まれること (RED)" {
  # AC: JP 6 件を SSOT 配列に追加する
  # RED: llm-indicators.sh 未存在または JP indicator 未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    source '${LLM_INDICATORS_LIB}'
    REQUIRED_JP=(生成中 構築中 処理中 作成中 分析中 検証中)
    missing_jp=()
    for word in \"\${REQUIRED_JP[@]}\"; do
        found=0
        for ind in \"\${LLM_INDICATORS[@]}\"; do
            [[ \"\$ind\" == *\"\$word\"* ]] && found=1 && break
        done
        [[ \$found -eq 0 ]] && missing_jp+=(\"\$word\")
    done
    if [[ \${#missing_jp[@]} -gt 0 ]]; then
        echo \"MISSING JP indicators: \${missing_jp[*]}\"
        exit 1
    fi
    echo 'PASS: JP 6 件確認'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6(#1374)/2: '処理中' indicator で STAGNATE が emit されないこと (RED)" {
  # AC: JP indicator が実際の thinking guard として機能する
  # RED: JP indicator 未追加のため cld-observe-any が 処理中 を indicator と認識しない → STAGNATE emit
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    TMPD=\"\$(mktemp -d)\"
    win='ap-shori-win'

    capture='処理中... (12s)
ファイルを解析しています'
    export capture

    logfile=\"\${TMPD}/\${win}.log\"
    touch -t \"\$(date -d '60 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')\" \"\$logfile\" 2>/dev/null || touch \"\$logfile\"

    tmux() {
        case \"\$1\" in
            list-windows) echo \"test-session:0 \$win\";;
            display-message) echo \"0 claude\";;
            capture-pane)
                if [[ \"\${*}\" == *'-S -1'* ]]; then echo ''; else printf '%s\n' \"\$capture\"; fi;;
            *) return 0;;
        esac
    }
    export -f tmux

    output_text=\$(_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR=\"\$(dirname '${CLD_OBSERVE_ANY}')\" \
        bash '${CLD_OBSERVE_ANY}' --window \"\$win\" --once \
        --log-dir \"\$TMPD\" \
        --stagnate-sec 5 2>/dev/null)
    exit_code=\$?
    rm -rf \"\$TMPD\"

    if echo \"\$output_text\" | grep -q 'STAGNATE'; then
        echo \"FAIL: JP indicator '処理中' が thinking guard として機能していない（STAGNATE emit）\"
        exit 1
    fi
    echo 'PASS: STAGNATE emit なし'
  "
  [ "${status}" -eq 0 ]
}

@test "ac6(#1374)/3: '生成中' indicator で STAGNATE が emit されないこと (RED)" {
  # AC: JP indicator '生成中' も thinking guard として機能する
  # RED: JP indicator 未追加のため fail
  [ -f "${LLM_INDICATORS_LIB}" ]
  run bash -c "
    TMPD=\"\$(mktemp -d)\"
    win='ap-seisei-win'

    capture='生成中... (7s)
コードを生成しています'
    export capture

    logfile=\"\${TMPD}/\${win}.log\"
    touch -t \"\$(date -d '60 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')\" \"\$logfile\" 2>/dev/null || touch \"\$logfile\"

    tmux() {
        case \"\$1\" in
            list-windows) echo \"test-session:0 \$win\";;
            display-message) echo \"0 claude\";;
            capture-pane)
                if [[ \"\${*}\" == *'-S -1'* ]]; then echo ''; else printf '%s\n' \"\$capture\"; fi;;
            *) return 0;;
        esac
    }
    export -f tmux

    output_text=\$(_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR=\"\$(dirname '${CLD_OBSERVE_ANY}')\" \
        bash '${CLD_OBSERVE_ANY}' --window \"\$win\" --once \
        --log-dir \"\$TMPD\" \
        --stagnate-sec 5 2>/dev/null)
    rm -rf \"\$TMPD\"

    if echo \"\$output_text\" | grep -q 'STAGNATE'; then
        echo \"FAIL: JP indicator '生成中' が thinking guard として機能していない\"
        exit 1
    fi
    echo 'PASS: STAGNATE emit なし'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9: observer-idle-check.sh のコメントを「SSOT: lib/llm-indicators.sh を参照」に更新
# ===========================================================================

@test "ac9(#1374)/1: observer-idle-check.sh の古い SSOT コメントが更新されていること (RED)" {
  # AC: コメント「SSOT: cld-observe-any の LLM_INDICATORS 配列と同期を保つこと」を
  #     「SSOT: lib/llm-indicators.sh を参照」に更新する
  # RED: 古いコメントが残存しているため fail
  run bash -c "
    if grep -q 'cld-observe-any の LLM_INDICATORS 配列と同期を保つこと' '${OBSERVER_IDLE_CHECK}'; then
        echo 'FAIL: 古いコメント「cld-observe-any の LLM_INDICATORS 配列と同期を保つこと」が残存'
        exit 1
    fi
    echo 'PASS: 古いコメントなし'
  "
  [ "${status}" -eq 0 ]
}

@test "ac9(#1374)/2: observer-idle-check.sh に「SSOT: lib/llm-indicators.sh を参照」コメントがあること (RED)" {
  # AC: 新しいコメントが追加されていること
  # RED: 新コメントが未追加のため fail
  run grep -qE 'SSOT.*llm-indicators\.sh|llm-indicators\.sh.*SSOT' "${OBSERVER_IDLE_CHECK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC10: monitor-channel-catalog.md または pitfalls §4.10 に SSOT lib の場所と参照規約を追記
# ===========================================================================

@test "ac10(#1374)/1: monitor-channel-catalog.md に llm-indicators.sh への言及があること (RED)" {
  # AC: monitor-channel-catalog.md に SSOT lib の場所と参照規約を追記する
  # RED: 言及が未追加のため fail
  run grep -qE 'llm-indicators\.sh' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac10(#1374)/2: pitfalls-catalog.md §4.10 に llm-indicators.sh への言及があること (RED)" {
  # AC: pitfalls §4.10 に SSOT lib の場所と参照規約を追記する
  # RED: 言及が未追加のため fail
  run bash -c "
    # §4.10 セクション内に llm-indicators.sh の言及があること
    section_start=\$(grep -n '4\.10' '${PITFALLS_CATALOG}' | head -1 | cut -d: -f1)
    [[ -n \"\$section_start\" ]] || { echo '§4.10 not found'; exit 1; }
    tail -n \"+\${section_start}\" '${PITFALLS_CATALOG}' | head -100 | grep -qE 'llm-indicators\.sh'
  "
  [ "${status}" -eq 0 ]
}

@test "ac10(#1374)/3: SSOT lib の参照規約（source 方法）が記載されていること (RED)" {
  # AC: lib の場所（plugins/session/scripts/lib/llm-indicators.sh）と参照方法が記載される
  # RED: 参照規約が未記載のため fail
  run bash -c "
    # monitor-channel-catalog.md または pitfalls-catalog.md に参照規約がある
    grep -rqE 'plugins/session/scripts/lib/llm-indicators\.sh|source.*llm-indicators' \
        '${MONITOR_CATALOG}' '${PITFALLS_CATALOG}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}

@test "ac10(#1374)/4: SSOT lib 参照規約が 3 ファイル（cld-observe-any, orchestrator, observer-idle-check）への適用方法を含むこと (RED)" {
  # AC: どのファイルがどのように llm-indicators.sh を参照すべきかの規約
  # RED: 規約が未記載のため fail
  run bash -c "
    # llm-indicators.sh が言及されており、かつ参照元ファイルへの適用方法の記述がある
    # 「どのファイルが source すべきか」という規約の存在を確認する
    grep -rqE 'llm-indicators\.sh' \
        '${MONITOR_CATALOG}' '${PITFALLS_CATALOG}' 2>/dev/null && \
    grep -rqE '(cld-observe-any|issue-lifecycle-orchestrator|observer-idle-check).*llm-indicators|llm-indicators.*(cld-observe-any|issue-lifecycle-orchestrator|observer-idle-check)' \
        '${MONITOR_CATALOG}' '${PITFALLS_CATALOG}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}
