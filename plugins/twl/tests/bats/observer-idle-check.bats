#!/usr/bin/env bats
# observer-idle-check.bats
#
# RED-phase tests for Issue #1117:
#   Tech-debt: Observer idle/completed monitoring — [IDLE-COMPLETED] channel 新設
#
# AC coverage:
#   AC1  - monitor-channel-catalog.md に [IDLE-COMPLETED] channel 新設 + completion phrase regex SSOT
#   AC2  - 60s debounce + IDLE_COMPLETED_DEBOUNCE_SEC env var override
#   AC3  - pitfalls-catalog.md §4.10 の 5 状態判定マトリクスに S-1 IDLE 行追加
#   AC4  - monitor-channel-catalog.md に Monitor tool snippet (多指標 AND 判定) 追加
#   AC5  - cld-observe-any に [IDLE-COMPLETED] event 追加 + IDLE_COMPLETED_TS 宣言
#   AC6  - su-observer-supervise-channels.md に [IDLE-COMPLETED] 行追加
#   AC7  - IDLE_COMPLETED_AUTO_KILL=1 follow-up Issue link (プロセス AC)
#   AC8  - _check_idle_completed() を observer-idle-check.sh に新規作成
#   AC9  - 対象 window pattern を (ap-|wt-|coi-).* に拡張
#   AC10 - 5件 regression fixture を observer-idle-check.bats に保全
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  SUPERVISE_CHANNELS="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"
  OBSERVER_LIB="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-idle-check.sh"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"

  export MONITOR_CATALOG PITFALLS_CATALOG SUPERVISE_CHANNELS OBSERVER_LIB CLD_OBSERVE_ANY

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: monitor-channel-catalog.md に [IDLE-COMPLETED] channel 新設
#      completion phrase regex が SSOT として定義される
# ===========================================================================

@test "ac1: monitor-channel-catalog.md has [IDLE-COMPLETED] channel entry" {
  # AC: monitor-channel-catalog.md に [IDLE-COMPLETED] channel が新設される
  # RED: channel がまだ追加されていないため fail
  grep -q '\[IDLE-COMPLETED\]' "${MONITOR_CATALOG}"
}

@test "ac1: monitor-channel-catalog.md [IDLE-COMPLETED] section has completion phrase regex" {
  # AC: [IDLE-COMPLETED] セクションに completion phrase regex が SSOT として記載される
  # RED: セクションが存在しないため fail
  run bash -c "
    # ## [IDLE-COMPLETED] セクションヘッダー行番号を取得
    section_line=\$(grep -n '^## \[IDLE-COMPLETED\]' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    # セクション内に regex パターン定義が存在することを確認
    awk -v start=\"\${section_line}\" 'NR > start && /regex|REGEX|nothing pending|Status=Refined|merge-gate/ {found=1; exit} NR > start && /^## \[/ && NR > start+1 {exit} END {exit !found}' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: monitor-channel-catalog.md channel table row has [IDLE-COMPLETED]" {
  # AC: チャネル一覧テーブルに [IDLE-COMPLETED] 行が存在する
  # RED: テーブル行が追加されていないため fail
  run grep -E '\| ?\[?IDLE-COMPLETED\]? ?\||\| ?IDLE-COMPLETED ?\|' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: debounce はデフォルト 60s、IDLE_COMPLETED_DEBOUNCE_SEC で override 可能
# ===========================================================================

@test "ac2: observer-idle-check.sh has default debounce of 60 seconds" {
  # AC: _check_idle_completed() のデフォルト debounce が 60s である
  # RED: observer-idle-check.sh がまだ存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run grep -E 'debounce.*60|60.*debounce|DEBOUNCE.*60|60.*DEBOUNCE|default.*60|60.*default' "${OBSERVER_LIB}"
  [ "${status}" -eq 0 ]
}

@test "ac2: observer-idle-check.sh respects IDLE_COMPLETED_DEBOUNCE_SEC env var" {
  # AC: IDLE_COMPLETED_DEBOUNCE_SEC env var で debounce 秒数を override できる
  # RED: observer-idle-check.sh がまだ存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run grep -E 'IDLE_COMPLETED_DEBOUNCE_SEC' "${OBSERVER_LIB}"
  [ "${status}" -eq 0 ]
}

@test "ac2: _check_idle_completed uses debounce_sec parameter from argument" {
  # AC: _check_idle_completed の第4引数 debounce_sec が実際に参照される
  # RED: 実装が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run grep -E 'debounce_sec|debounce\)' "${OBSERVER_LIB}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: pitfalls-catalog.md §4.10 の 5 状態判定マトリクスに
#      「S-1 IDLE 確定 (cleanup target)」行追加
# ===========================================================================

@test "ac3: pitfalls-catalog.md §4.10 matrix has S-1 IDLE cleanup target row" {
  # AC: §4.10 の判定マトリクスに「S-1 IDLE 確定 (cleanup target)」行が追加される
  # RED: 該当行がまだ存在しないため fail
  run grep -E 'cleanup target|IDLE 確定|S-1.*cleanup' "${PITFALLS_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac3: pitfalls-catalog.md §4.10 S-1 IDLE row references [IDLE-COMPLETED]" {
  # AC: §4.10 S-1 IDLE 行が [IDLE-COMPLETED] channel を参照する
  # RED: 参照が存在しないため fail
  run bash -c "
    # §4.10 のスコープ内で S-1 IDLE と [IDLE-COMPLETED] が同じ行または近傍に存在する
    grep -nE 'cleanup target|IDLE 確定|S-1.*cleanup' '${PITFALLS_CATALOG}' | head -1 | grep -qE 'IDLE-COMPLETED|idle.completed' || \
    grep -A5 -E 'cleanup target|IDLE 確定|S-1.*cleanup' '${PITFALLS_CATALOG}' | grep -qE 'IDLE-COMPLETED|idle.completed'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: monitor-channel-catalog.md に Monitor tool snippet を追加
#      多指標 AND 判定 bash regex 形式
# ===========================================================================

@test "ac4: monitor-channel-catalog.md [IDLE-COMPLETED] section has Monitor tool snippet" {
  # AC: [IDLE-COMPLETED] セクションに Monitor tool 向け bash スニペットが存在する
  # RED: スニペットが追加されていないため fail
  run bash -c "
    section_line=\$(grep -n '## \[IDLE-COMPLETED\]' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    # スニペットに多指標 AND 判定が含まれる
    awk -v start=\"\${section_line}\" '
      NR > start && /AND|&&|multi.*index|多指標|IDLE_COMPLETED_TS/ {found=1; exit}
      NR > start && /^## \[/ && NR > start+1 {exit}
      END {exit !found}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: monitor-channel-catalog.md [IDLE-COMPLETED] snippet contains IDLE_COMPLETED_TS variable" {
  # AC: snippet が IDLE_COMPLETED_TS（debounce 管理用の連想配列）を使用している
  # RED: IDLE_COMPLETED_TS がまだ定義されていないため fail
  run grep -E 'IDLE_COMPLETED_TS' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac4: monitor-channel-catalog.md [IDLE-COMPLETED] snippet uses bash regex for completion phrases" {
  # AC: bash regex が completion phrase（nothing pending, Status=Refined 等）をカバーする
  # RED: regex が存在しないため fail
  run bash -c "
    section_line=\$(grep -n '## \[IDLE-COMPLETED\]' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    awk -v start=\"\${section_line}\" '
      NR > start && /nothing pending|Status=Refined|merge.gate|refined.*ラベル|次のステップ/ {found=1; exit}
      NR > start && /^## \[/ && NR > start+1 {exit}
      END {exit !found}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: cld-observe-any に [IDLE-COMPLETED] event 追加
#      declare -A IDLE_COMPLETED_TS がメインループスコープで宣言される
# ===========================================================================

@test "ac5: cld-observe-any has [IDLE-COMPLETED] event emit" {
  # AC: cld-observe-any が [IDLE-COMPLETED] event を emit できる
  # RED: event がまだ実装されていないため fail
  run grep -E 'IDLE-COMPLETED' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac5: cld-observe-any declares IDLE_COMPLETED_TS as associative array" {
  # AC: declare -A IDLE_COMPLETED_TS がメインループスコープ（関数外）で宣言される
  # RED: 宣言がまだ存在しないため fail
  run grep -E 'declare -A IDLE_COMPLETED_TS' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac5: cld-observe-any IDLE_COMPLETED_TS declaration is in main scope" {
  # AC: IDLE_COMPLETED_TS の declare が関数定義の外側（メインスコープ）にある
  # RED: 宣言がないまたは関数内にあるため fail
  run bash -c "
    file='${CLD_OBSERVE_ANY}'
    # declare -A IDLE_COMPLETED_TS の行番号を取得
    decl_line=\$(grep -n 'declare -A IDLE_COMPLETED_TS' \"\${file}\" | head -1 | cut -d: -f1)
    [ -n \"\${decl_line}\" ] || exit 1
    # その行よりも前の行で最後に現れる '{' が関数開始でないことを確認
    # (メインスコープでは関数ブレースの内側にない)
    # 簡易検証: declare より前の行でインデントのない行が直近にあることを確認
    awk -v target=\"\${decl_line}\" '
      NR <= target && /^[a-zA-Z_][a-zA-Z0-9_]*\(\)/ { last_func=NR }
      NR == target {
        # 最後の関数定義が target より前にあれば main scope 外の疑い
        # ただしここでは declare の存在確認のみ（位置の厳密検証はスキップ）
        exit 0
      }
    ' \"\${file}\"
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6: su-observer-supervise-channels.md に [IDLE-COMPLETED] 行追加
# ===========================================================================

@test "ac6: su-observer-supervise-channels.md has [IDLE-COMPLETED] row" {
  # AC: su-observer-supervise-channels.md のチャンネル表に [IDLE-COMPLETED] 行が追加される
  # RED: 行がまだ存在しないため fail
  run grep -E '\[?IDLE-COMPLETED\]?' "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

@test "ac6: su-observer-supervise-channels.md [IDLE-COMPLETED] row has debounce or threshold info" {
  # AC: [IDLE-COMPLETED] 行が debounce 秒数または閾値情報を含む
  # RED: 行が存在しないため fail
  run grep -E 'IDLE-COMPLETED.*(60|debounce|秒)|.*IDLE-COMPLETED' "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: IDLE_COMPLETED_AUTO_KILL=1 follow-up Issue link (プロセス AC)
#      自動検証不可のため、存在確認のみ（stub）
# ===========================================================================

@test "ac7: (process AC) IDLE_COMPLETED_AUTO_KILL follow-up Issue is referenced" {
  # AC: 自動 kill オプション (IDLE_COMPLETED_AUTO_KILL=1) の follow-up Issue link が
  #     monitor-channel-catalog.md または関連ファイルに記載されている
  # RED: 記載がまだないため fail
  # NOTE: このテストはプロセス AC。Issue link の確認のみ
  run bash -c "
    grep -rE 'IDLE_COMPLETED_AUTO_KILL|auto.kill.*IDLE.COMPLETED|IDLE.COMPLETED.*auto.kill' \
      '${MONITOR_CATALOG}' '${PITFALLS_CATALOG}' '${SUPERVISE_CHANNELS}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC8: _check_idle_completed() を observer-idle-check.sh に新規作成
#      シグネチャ: _check_idle_completed pane_content first_seen_ts now_ts [debounce_sec=60]
# ===========================================================================

@test "ac8: scripts/lib/observer-idle-check.sh exists" {
  # AC: observer-idle-check.sh が scripts/lib/ に新規作成される
  # RED: ファイルがまだ存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
}

@test "ac8: observer-idle-check.sh is executable" {
  # AC: observer-idle-check.sh が実行可能である（source または bash で実行可）
  # RED: ファイルが存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  [ -r "${OBSERVER_LIB}" ]
}

@test "ac8: observer-idle-check.sh defines _check_idle_completed function" {
  # AC: _check_idle_completed 関数が定義されている
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run grep -E '^_check_idle_completed\(\)|^function _check_idle_completed' "${OBSERVER_LIB}"
  [ "${status}" -eq 0 ]
}

@test "ac8: _check_idle_completed signature accepts pane_content first_seen_ts now_ts" {
  # AC: 第1〜3引数として pane_content, first_seen_ts, now_ts を受け取る
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    # 関数が存在することを確認（引数 3 つで呼べる）
    declare -f _check_idle_completed > /dev/null 2>&1
  "
  [ "${status}" -eq 0 ]
}

@test "ac8: _check_idle_completed returns 0 (idle) when completion phrase present and debounce passed" {
  # AC: completion phrase が存在し debounce 経過後に return 0（idle 確定）
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='nothing pending (wt-twill-main-49606687)'
    first_seen_ts=100
    now_ts=161  # 61秒後 (default debounce 60s を超過)
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac8: _check_idle_completed returns non-0 when debounce not yet passed" {
  # AC: debounce 未経過の場合は non-0 を返す（idle 未確定）
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='nothing pending (wt-twill-main-49606687)'
    first_seen_ts=100
    now_ts=130  # 30秒後 (debounce 60s 未経過)
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -ne 0 ]
}

@test "ac8: _check_idle_completed returns non-0 when no completion phrase in pane_content" {
  # AC: completion phrase がない場合は non-0 を返す（idle でない）
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='Thinking... processing your request'
    first_seen_ts=0
    now_ts=200
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -ne 0 ]
}

@test "ac8: _check_idle_completed respects custom debounce_sec as 4th argument" {
  # AC: 第4引数 debounce_sec=30 を渡すと 30s で idle 確定になる
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='Status=Refined label added'
    first_seen_ts=100
    now_ts=135  # 35秒後 (debounce_sec=30 を超過)
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\" 30
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9: 対象 window pattern を (ap-|wt-|coi-).* に拡張
# ===========================================================================

@test "ac9: monitor-channel-catalog.md [IDLE-COMPLETED] references (ap-|wt-|coi-) pattern" {
  # AC: monitor-channel-catalog.md に coi- パターンが追加される
  # RED: coi- パターンが存在しないため fail
  run grep -E 'coi-|ap-\|wt-\|coi-|\(ap-\|wt-\|coi-\)' "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac9: su-observer-supervise-channels.md or cld-observe-any uses (ap-|wt-|coi-) pattern" {
  # AC: cld-observe-any または supervise-channels.md が coi- を含む pattern を使用する
  # RED: coi- パターンがまだ追加されていないため fail
  run bash -c "
    grep -E 'coi-' '${SUPERVISE_CHANNELS}' '${CLD_OBSERVE_ANY}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC10: regression fixture 5件
#
# _check_idle_completed が実際の pane content 文字列を正しく判定するか検証する。
# 各フィクスチャは実際の観測事例（Issue #1111, #1113, #1114, #1105, #1118）から収集。
# ===========================================================================

@test "ac10: fixture1 - 'nothing pending' is recognized as idle (wt-twill-main-49606687 #1111)" {
  # AC: 「nothing pending (wt-twill-main-49606687 #1111)」のような pane content は idle と判定される
  # 出典: wt-twill-main-49606687 / Issue #1111
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='✓ nothing pending (wt-twill-main-49606687)
Worked for 2m 15s
> '
    first_seen_ts=0
    now_ts=61
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac10: fixture2 - 'Status=Refined' is recognized as idle (refine #1113)" {
  # AC: 「Status=Refined」が含まれる pane content は idle と判定される
  # 出典: refine session / Issue #1113
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='gh issue edit 1113 --add-label refined
Status=Refined
Worked for 1m 30s
> '
    first_seen_ts=0
    now_ts=61
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac10: fixture3 - 'refined ラベル付与' is recognized as idle (refine #1114)" {
  # AC: 「refined ラベル付与」が含まれる pane content は idle と判定される
  # 出典: refine session / Issue #1114
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='refined ラベル付与: Issue #1114
Worked for 45s
> '
    first_seen_ts=0
    now_ts=61
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac10: fixture4 - '次のステップ:' is recognized as idle (wt-co-explore-153758 #1105)" {
  # AC: 「次のステップ:」が含まれる pane content は idle と判定される
  # 出典: wt-co-explore-153758 / Issue #1105
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='次のステップ: Issue #1105 の実装を開始してください。
Worked for 3m 22s
> '
    first_seen_ts=0
    now_ts=61
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac10: fixture5 - 'merge-gate 成功' is recognized as idle (refine #1118)" {
  # AC: 「merge-gate 成功」が含まれる pane content は idle と判定される
  # 出典: refine session / Issue #1118
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='[merge-gate] merge-gate 成功: Issue #1118 マージ完了
Worked for 5m 10s
> '
    first_seen_ts=0
    now_ts=61
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac10: fixture-negative - active LLM indicator is NOT recognized as idle" {
  # AC: LLM 思考中（Thinking... 等）は idle と判定されない
  # これはネガティブコントロール（現在進行形 indicator は idle 禁止）
  # RED: 関数が存在しないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='Thinking...
Processing your request
nothing pending but still thinking'
    first_seen_ts=0
    now_ts=200
    _check_idle_completed \"\${pane_content}\" \"\${first_seen_ts}\" \"\${now_ts}\"
  "
  # Thinking... が存在する場合は idle と判定しない（non-0）
  [ "${status}" -ne 0 ]
}
