#!/usr/bin/env bats
# issue-1243-controller-primary-signal.bats
#
# RED-phase tests for Issue #1243:
#   feat(observer): observer 1189 implementation gap 対処
#     - monitor-channel-catalog.md に controller type 別 primary completion signal mapping 追加
#     - pilot-completion-signals.md に co-issue refine 専用行追加
#     - step0-monitor-bootstrap.sh _emit_start_commands() に export IDLE_COMPLETED_AUTO_KILL=1 追加
#     - SKILL.md Step 0 step 6.6 (controller type 判定 + primary signal mapping 参照 MUST) 追加
#
# AC coverage:
#   AC1 - monitor-channel-catalog.md に「controller type 別 primary completion signal mapping」section 追加
#   AC2 - pilot-completion-signals.md table に co-issue refine 専用行が新規行として追加
#   AC3 - step0-monitor-bootstrap.sh _emit_start_commands() stdout に "export IDLE_COMPLETED_AUTO_KILL=1" が含まれる
#   AC4 - SKILL.md Step 0 step 6.5 (L40) 直後に step 6.6 として controller type 判定 + primary signal mapping 参照 MUST 追加
#   AC5 - bats テスト自身が plugins/twl/tests/bats/issue-1243-controller-primary-signal.bats として存在
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
  PILOT_SIGNALS="${REPO_ROOT}/skills/su-observer/refs/pilot-completion-signals.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  BOOTSTRAP_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/step0-monitor-bootstrap.sh"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1243-controller-primary-signal.bats"

  export MONITOR_CATALOG PILOT_SIGNALS SKILL_MD BOOTSTRAP_SCRIPT THIS_BATS
}

# ===========================================================================
# AC1: monitor-channel-catalog.md に「controller type 別 primary completion
#      signal mapping」section が追加されている
# ===========================================================================

@test "ac1: monitor-channel-catalog.md has 'controller type 別 primary completion signal mapping' section" {
  # AC: catalog に controller type 別 primary completion signal mapping セクションが存在する
  # RED: セクションがまだ追加されていないため fail
  run grep -qE 'controller type 別.*primary.*signal mapping|primary completion signal mapping|controller.*type.*別.*primary' \
    "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac1: primary completion signal mapping section contains at least co-autopilot and co-issue entries" {
  # AC: mapping に co-autopilot と co-issue の両エントリが含まれる
  # RED: セクション自体がないため fail
  run bash -c "
    # mapping セクション内に co-autopilot と co-issue の両方が列挙されている
    section_line=\$(grep -n 'controller type 別.*primary.*signal\|primary completion signal mapping\|controller.*type.*別.*primary' \
      '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    # セクション以降 30 行以内に co-autopilot が存在する
    awk -v s=\"\${section_line}\" 'NR >= s && NR < (s+30) && /co-autopilot/ {found=1; exit} END {exit !found}' \
      '${MONITOR_CATALOG}' || exit 1
    # セクション以降 30 行以内に co-issue が存在する
    awk -v s=\"\${section_line}\" 'NR >= s && NR < (s+30) && /co-issue/ {found=1; exit} END {exit !found}' \
      '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: primary completion signal mapping section documents primary signal per controller type" {
  # AC: mapping に各 controller type の primary signal が明記されている
  # RED: primary signal の記載がまだないため fail
  run bash -c "
    # 「primary」というキーワードが mapping セクション内のテーブルや説明に存在する
    section_line=\$(grep -n 'controller type 別.*primary.*signal\|primary completion signal mapping\|controller.*type.*別.*primary' \
      '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    awk -v s=\"\${section_line}\" '
      NR >= s && NR < (s+50) && /primary/ {count++}
      END {exit (count < 2)}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: pilot-completion-signals.md table に co-issue refine 専用行が
#      新規行として追加されている
# ===========================================================================

@test "ac2: pilot-completion-signals.md table has co-issue refine dedicated row" {
  # AC: table に co-issue refine 専用行が存在する
  # RED: 専用行がまだ追加されていないため fail
  run grep -qE 'co-issue.*refine|refine.*co-issue' "${PILOT_SIGNALS}"
  [ "${status}" -eq 0 ]
}

@test "ac2: co-issue refine row in pilot-completion-signals.md is a new table row (not a comment)" {
  # AC: co-issue refine の行がテーブル行（| で区切られた形式）として追加されている
  # RED: テーブル行が存在しないため fail
  run bash -c "
    # | co-issue (refine) | ... | のテーブル行形式で存在する
    grep -qE '^\|[^|]*co-issue[^|]*refine[^|]*\|' '${PILOT_SIGNALS}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: co-issue refine row includes signal text (what to look for in log)" {
  # AC: co-issue refine 行に Signal テキスト（検知文字列）が記載されている
  # RED: 行自体がないため fail
  run bash -c "
    # co-issue refine 行が 4 カラム以上のテーブル行として存在し、3番目のカラムが空でない
    match=\$(grep -E '^\|[^|]*co-issue[^|]*refine[^|]*\|' '${PILOT_SIGNALS}' | head -1)
    [ -n \"\${match}\" ] || exit 1
    # 3 番目のカラム（\$4）に内容がある（空カラムでない）
    col3=\$(echo \"\${match}\" | awk -F'|' '{gsub(/^ +| +\$/, \"\", \$4); print \$4}')
    [ -n \"\${col3}\" ] && [ \"\${col3}\" != '...' ] && [ \"\${col3}\" != 'TBD' ]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: step0-monitor-bootstrap.sh の _emit_start_commands() が stdout に
#      出力するコマンド文字列に「export IDLE_COMPLETED_AUTO_KILL=1」が含まれる
#      （シェル自体での export ではなく、echo で文字列として emit する）
# ===========================================================================

@test "ac3: _emit_start_commands() stdout contains 'export IDLE_COMPLETED_AUTO_KILL=1' as emitted string" {
  # AC: _emit_start_commands() の stdout に "export IDLE_COMPLETED_AUTO_KILL=1" が含まれる
  # RED: emit 行がまだ追加されていないため fail
  run bash -c "
    # 関数定義部分のみを抽出して eval し、_emit_start_commands の stdout を検証
    func_def=\$(sed -n '/_emit_start_commands()/,/^}/p' '${BOOTSTRAP_SCRIPT}' | head -50)
    eval \"\${func_def}\"
    _emit_start_commands 2>/dev/null | grep -qF 'export IDLE_COMPLETED_AUTO_KILL=1'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: bootstrap script file contains echo of 'export IDLE_COMPLETED_AUTO_KILL=1' in _emit_start_commands" {
  # AC: スクリプトファイルに echo "export IDLE_COMPLETED_AUTO_KILL=1" の行が _emit_start_commands 内に存在
  # RED: echo 行がまだ追加されていないため fail
  run bash -c "
    start_line=\$(grep -n '_emit_start_commands()' '${BOOTSTRAP_SCRIPT}' | head -1 | cut -d: -f1)
    [ -n \"\${start_line}\" ] || exit 1
    # awk: 関数内に echo で IDLE_COMPLETED_AUTO_KILL=1 を出力する行を検索
    awk -v s=\"\${start_line}\" '
      NR >= s && /echo.*IDLE_COMPLETED_AUTO_KILL=1|printf.*IDLE_COMPLETED_AUTO_KILL=1/ {found=1}
      NR > s && /^}/ {exit}
      END {exit !found}
    ' '${BOOTSTRAP_SCRIPT}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: _emit_start_commands() does not export IDLE_COMPLETED_AUTO_KILL in the shell itself" {
  # AC: 関数はシェル自体で export するのではなく、文字列として emit する
  # RED: 正しい実装（echo 経由の emit）がまだないため fail
  # 注: この test は「シェル exec での export」がないことを確認（emit であるべき）
  run bash -c "
    # 関数定義内に直接 export IDLE_COMPLETED_AUTO_KILL（echo なし）がないことを確認
    start_line=\$(grep -n '_emit_start_commands()' '${BOOTSTRAP_SCRIPT}' | head -1 | cut -d: -f1)
    [ -n \"\${start_line}\" ] || exit 1
    # echo なしの直接 export 行がない = 0 件であることを確認
    direct_export=\$(awk -v s=\"\${start_line}\" '
      NR > s && /^}/ {exit}
      NR >= s && /^[[:space:]]*export IDLE_COMPLETED_AUTO_KILL/ && !/echo/ {print}
    ' '${BOOTSTRAP_SCRIPT}')
    [ -z \"\${direct_export}\" ]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: SKILL.md の Step 0 step 6.5（L40）直後に step 6.6 として
#      「controller type 判定 + primary signal mapping 参照の MUST 規定」が追加される
# ===========================================================================

@test "ac4: SKILL.md has step 6.6 after step 6.5 in Step 0" {
  # AC: Step 0 step 6.5 の直後に 6.6 が存在する
  # RED: step 6.6 がまだ追加されていないため fail
  run grep -qE '^6\.6\.' "${SKILL_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac4: SKILL.md step 6.6 references controller type 判定" {
  # AC: step 6.6 に「controller type 判定」の記載がある
  # RED: step 6.6 がまだ追加されていないため fail
  run bash -c "
    step66_line=\$(grep -n '^6\.6\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step66_line}\" ] || exit 1
    # 6.6 の行に controller type 判定が含まれる
    awk -v l=\"\${step66_line}\" 'NR == l && /controller.*type.*判定|controller type|type.*判定/' '${SKILL_MD}' | grep -q .
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: SKILL.md step 6.6 references primary signal mapping" {
  # AC: step 6.6 に「primary signal mapping 参照」の記載がある
  # RED: step 6.6 がまだ追加されていないため fail
  run bash -c "
    step66_line=\$(grep -n '^6\.6\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step66_line}\" ] || exit 1
    # 6.6 の行または直後 3 行以内に primary signal mapping 参照がある
    awk -v s=\"\${step66_line}\" '
      NR >= s && NR < (s+4) && /primary.*signal.*mapping|signal.*mapping|monitor-channel-catalog/ {found=1; exit}
      END {exit !found}
    ' '${SKILL_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: SKILL.md step 6.6 contains MUST keyword for primary signal mapping reference" {
  # AC: step 6.6 に「MUST」または相当する必須規定が含まれる
  # RED: MUST 規定がまだないため fail
  run bash -c "
    step66_line=\$(grep -n '^6\.6\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step66_line}\" ] || exit 1
    # 6.6 前後 3 行以内に MUST が含まれる
    awk -v s=\"\${step66_line}\" '
      NR >= s && NR < (s+4) && /MUST/ {found=1; exit}
      END {exit !found}
    ' '${SKILL_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: SKILL.md step 6.6 is placed immediately after step 6.5 (L40)" {
  # AC: step 6.6 が step 6.5 (L40) の直後に配置されている（step 7 より前）
  # RED: step 6.6 がまだ存在しないため fail
  run bash -c "
    step65_line=\$(grep -n '^6\.5\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    step66_line=\$(grep -n '^6\.6\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    step7_line=\$(grep -n '^7\.' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step65_line}\" ] || exit 1
    [ -n \"\${step66_line}\" ] || exit 1
    # 6.6 は 6.5 より後、7. より前に存在する
    [ \"\${step66_line}\" -gt \"\${step65_line}\" ] || exit 1
    [ -z \"\${step7_line}\" ] || [ \"\${step66_line}\" -lt \"\${step7_line}\" ]
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: bats テスト自身が存在している（自己確認）
# ===========================================================================

@test "ac5: this bats test file exists at expected path" {
  # AC: bats ファイルが plugins/twl/tests/bats/issue-1243-controller-primary-signal.bats として存在する
  # GREEN: このファイル自体が存在するため、実行時点では pass する
  [ -f "${THIS_BATS}" ]
}
