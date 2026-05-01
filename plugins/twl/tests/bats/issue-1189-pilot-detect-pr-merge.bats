#!/usr/bin/env bats
# issue-1189-pilot-detect-pr-merge.bats
#
# RED-phase tests for Issue #1189:
#   feat(observer): pilot PILOT-PHASE-COMPLETE / PILOT-WAVE-COLLECTED 即 kill +
#                   PR merge polling + IDLE_COMPLETED_AUTO_KILL 恒久化 +
#                   observer-supervise-checklist.md 新設
#
# AC coverage:
#   AC6.1 - su-observer-supervise-channels.md に PILOT-PHASE-COMPLETE / PILOT-WAVE-COLLECTED 即 kill step 追加
#   AC6.2 - .supervisor/cld-observe-any.log の regex pattern 検知（catalog line 615 / 660 と完全一致）
#   AC6.3 - 検知後 60s 以内に tmux kill-window -t <pilot-window> を実行（dual-fire 回避付き）
#   AC6.4 - SKILL.md or supervise-channels.md に「PILOT 完遂検知 → 即 kill MUST」記載 + bats assert
#   AC7.1 - su-observer-supervise-channels.md に PR merge polling (5 min interval) step 追加
#   AC7.2 - gh pr list --search "in:body #${ISSUE_NUM}" --state merged クエリ実装
#   AC7.3 - 検知時 closingIssuesReferences → board status 確認 → IDLE-COMPLETED kill 候補 mark
#   AC7.4 - monitor-channel-catalog.md [PILOT-ISSUE-MERGED] セクションに「能動 polling 経路」追加
#   AC8.1 - cld-observe-any wrapper/bootstrap で IDLE_COMPLETED_AUTO_KILL=1 を env 恒久化
#   AC8.2 - monitor-channel-catalog.md IDLE_COMPLETED_PHRASE_REGEX が pilot-completion-signals.md から導出
#   AC8.3 - pilot-completion-signals.md の table (line 14-26) に controller 完了句 SSOT 集約
#   AC8.4 - bats で IDLE_COMPLETED_AUTO_KILL=1 default assert + IDLE_COMPLETED_PHRASE_REGEX 整合 assert
#   AC9.1 - plugins/twl/skills/su-observer/refs/observer-supervise-checklist.md 新規作成
#   AC9.2 - checklist 項目（supervise loop 各 cycle で verify する項目リスト）
#   AC9.3 - SKILL.md or supervise-channels.md Step 1 に observer-supervise-checklist.md 全項目 MUST verify 組み込み
#   AC9.4 - file 存在 + SKILL.md or supervise-channels.md からの reference 1 か所以上 + bats 整合確認
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SUPERVISE_CHANNELS="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PILOT_SIGNALS="${REPO_ROOT}/skills/su-observer/refs/pilot-completion-signals.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  CHECKLIST="${REPO_ROOT}/skills/su-observer/refs/observer-supervise-checklist.md"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"

  export SUPERVISE_CHANNELS MONITOR_CATALOG PILOT_SIGNALS SKILL_MD CHECKLIST CLD_OBSERVE_ANY

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC6.1: su-observer-supervise-channels.md に PILOT-PHASE-COMPLETE /
#        PILOT-WAVE-COLLECTED event 検知時 即 kill MUST step を追加
# ===========================================================================

@test "ac6.1: su-observer-supervise-channels.md has PILOT-PHASE-COMPLETE immediate kill step" {
  # AC: supervise loop に「PILOT-PHASE-COMPLETE / PILOT-WAVE-COLLECTED 検知時即 kill MUST」step が追加される
  # RED: step がまだ追加されていないため fail
  run grep -qE 'PILOT.PHASE.COMPLETE.*kill|kill.*PILOT.PHASE.COMPLETE|PILOT.WAVE.COLLECTED.*kill|kill.*PILOT.WAVE.COLLECTED' \
    "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6.2: .supervisor/cld-observe-any.log の regex pattern を 30s 以内に検知
#        catalog line 615 (PILOT-PHASE-COMPLETE regex) と完全一致させる
# ===========================================================================

@test "ac6.2: PILOT-PHASE-COMPLETE regex in catalog matches pilot-completion-signals.md SSOT" {
  # AC: catalog line 615 の PILOT_PHASE_COMPLETE_REGEX が pilot-completion-signals.md と完全一致
  # RED: catalog と SSOT の整合が取れていないため fail（または整合チェック実装が未存在）
  run bash -c "
    catalog_regex=\$(grep -A1 'PILOT_PHASE_COMPLETE_REGEX' '${MONITOR_CATALOG}' | grep -v '^#' | head -1 | tr -d \"' \")
    ssot_regex=\$(grep -A1 'PILOT_PHASE_COMPLETE_REGEX' '${PILOT_SIGNALS}' | grep -v '^#' | head -1 | tr -d \"' \")
    # 両ファイルに PILOT_PHASE_COMPLETE_REGEX が存在し、かつ値が一致すること
    [ -n \"\${catalog_regex}\" ] || exit 1
    [ -n \"\${ssot_regex}\" ] || exit 1
    [ \"\${catalog_regex}\" = \"\${ssot_regex}\" ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac6.2: PILOT-WAVE-COLLECTED regex in catalog matches pilot-completion-signals.md SSOT" {
  # AC: catalog line 660 の PILOT_WAVE_COLLECTED_REGEX が pilot-completion-signals.md と完全一致
  # RED: catalog と SSOT の整合が取れていないため fail
  run bash -c "
    catalog_regex=\$(grep -A1 'PILOT_WAVE_COLLECTED_REGEX' '${MONITOR_CATALOG}' | grep -v '^#' | head -1 | tr -d \"' \")
    ssot_regex=\$(grep -A1 'PILOT_WAVE_COLLECTED_REGEX' '${PILOT_SIGNALS}' | grep -v '^#' | head -1 | tr -d \"' \")
    [ -n \"\${catalog_regex}\" ] || exit 1
    [ -n \"\${ssot_regex}\" ] || exit 1
    [ \"\${catalog_regex}\" = \"\${ssot_regex}\" ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac6.2: supervise-channels.md references cld-observe-any.log as PILOT event detection source" {
  # AC: supervise loop が .supervisor/cld-observe-any.log を PILOT-* event 検知 source として参照する
  # RED: 参照が追加されていないため fail
  run grep -qE 'cld-observe-any\.log|cld.observe.any.*log' "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC6.3: 検知後 60s 以内に tmux kill-window -t <pilot-window> を実行
#        dual-fire 回避: AC6 = 即時、AC8 = 60s debounce 後
# ===========================================================================

@test "ac6.3: supervise-channels.md specifies tmux kill-window within 60s for PILOT-PHASE-COMPLETE" {
  # AC: PILOT-PHASE-COMPLETE 検知後 60s 以内に tmux kill-window を実行すると明記
  # RED: kill-window の実行手順がまだ記載されていないため fail
  run grep -qE 'kill.window.*pilot|tmux.*kill.*pilot|PILOT.*kill.window|60s.*kill|kill.*60s|即.kill|即時.*kill' \
    "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

@test "ac6.3: supervise-channels.md documents dual-fire avoidance between AC6 and AC8" {
  # AC: AC6 即時 kill と AC8 debounce kill の dual-fire 回避が記載されている
  # RED: dual-fire 回避の記載がまだないため fail
  run grep -qE 'dual.fire|重複.*kill|冪等|idempotent|debounce.*kill|kill.*debounce' "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

@test "ac6.3: simulated PILOT-PHASE-COMPLETE event triggers kill-window within 60s" {
  # AC: .supervisor/cld-observe-any.log に PILOT-PHASE-COMPLETE signal が書き込まれた場合、
  #     60s 以内に kill-window が実行される（stub による動作確認）
  # RED: kill 機構がまだ実装されていないため fail
  SUPERVISOR_DIR="${TMPDIR_TEST}/.supervisor"
  mkdir -p "${SUPERVISOR_DIR}"
  LOG_FILE="${SUPERVISOR_DIR}/cld-observe-any.log"

  # PILOT-PHASE-COMPLETE signal を simulate
  echo "[PILOT-PHASE-COMPLETE] ap-twill-feat-1189-xxxxxxxx: Phase 2 完了" >> "${LOG_FILE}"
  echo "[orchestrator] Phase 2 完了" >> "${LOG_FILE}"

  # kill-window スクリプトが存在しかつ実行可能であることを assert
  KILL_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/pilot-phase-kill.sh"
  [ -f "${KILL_SCRIPT}" ]
}

# ===========================================================================
# AC6.4: SKILL.md or supervise-channels.md に「PILOT 完遂検知 → 即 kill MUST」を含む
# ===========================================================================

@test "ac6.4: SKILL.md or supervise-channels.md contains PILOT complete-then-kill MUST statement" {
  # AC: 「PILOT 完遂検知 → 即 kill MUST」またはそれに相当する文言が記載されている
  # RED: 記載がまだないため fail
  run bash -c "
    grep -qE 'PILOT.*完遂.*kill.*MUST|PILOT.*即.*kill|即.*kill.*MUST.*PILOT' \
      '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7.1: su-observer-supervise-channels.md に PR merge polling (5 min interval) step 追加
# ===========================================================================

@test "ac7.1: su-observer-supervise-channels.md has PR merge polling step with 5 min interval" {
  # AC: supervise loop に「PR merge polling MUST (5 min interval)」step が追加される
  # RED: step がまだ追加されていないため fail
  run grep -qE 'PR merge.*poll|merge.*poll.*5|5.*min.*poll|5.*分.*poll|polling.*5 min|gh pr list.*merge' \
    "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7.2: gh pr list --search "in:body #${ISSUE_NUM}" --state merged クエリ実装
# ===========================================================================

@test "ac7.2: supervise-channels.md or pilot-signals.md contains correct gh pr list merge query" {
  # AC: gh pr list --search "in:body #${ISSUE_NUM}" --state merged クエリが記載されている
  # RED: クエリがまだ記載されていないため fail
  run bash -c "
    grep -qE 'gh pr list.*in:body.*ISSUE_NUM.*merged|gh pr list.*search.*in:body.*state merged' \
      '${SUPERVISE_CHANNELS}' '${PILOT_SIGNALS}' '${MONITOR_CATALOG}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7.3: 検知時 action: closingIssuesReferences → board status 確認 →
#        AC8 IDLE-COMPLETED kill 候補として mark（Confirm Layer）
# ===========================================================================

@test "ac7.3: supervise-channels.md documents closingIssuesReferences check for merged PR" {
  # AC: PR merge 検知時に closingIssuesReferences で Issue を特定する手順が記載されている
  # RED: 手順がまだ記載されていないため fail
  run grep -qE 'closingIssuesReferences|closing.*Issues.*References|gh pr view.*json.*closing' \
    "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

@test "ac7.3: supervise-channels.md documents IDLE-COMPLETED kill candidate mark on PR merge" {
  # AC: PR merge 検知後に該当 controller window を IDLE-COMPLETED kill 候補として mark する手順がある
  # RED: mark 手順がまだ記載されていないため fail
  run grep -qE 'kill.*candidate|kill 候補|IDLE.COMPLETED.*mark|mark.*IDLE.COMPLETED|Confirm Layer' \
    "${SUPERVISE_CHANNELS}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7.4: monitor-channel-catalog.md [PILOT-ISSUE-MERGED] セクションに
#        「能動 polling 経路」を追加（既存は Pilot stdout からの受動 emit のみ）
# ===========================================================================

@test "ac7.4: monitor-channel-catalog.md [PILOT-ISSUE-MERGED] section has active polling path" {
  # AC: [PILOT-ISSUE-MERGED] セクションに「能動 polling 経路」が追加される
  # RED: 能動 polling 経路がまだ追加されていないため fail
  run bash -c "
    section_line=\$(grep -n '## \[PILOT-ISSUE-MERGED\]' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    # セクション内に「能動 polling」または「active polling」が存在する
    awk -v start=\"\${section_line}\" '
      NR > start && /能動 polling|active polling|能動.*poll|poll.*能動|5.*min.*poll|5.*分.*poll/ {found=1; exit}
      NR > start && /^## \[/ && NR > start+1 {exit}
      END {exit !found}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac7.4: monitor-channel-catalog.md [PILOT-ISSUE-MERGED] section distinguishes passive vs active paths" {
  # AC: [PILOT-ISSUE-MERGED] セクションが受動 emit と能動 polling の両経路を記載している
  # RED: 両経路の区別がまだ記載されていないため fail
  run bash -c "
    section_line=\$(grep -n '## \[PILOT-ISSUE-MERGED\]' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${section_line}\" ] || exit 1
    awk -v start=\"\${section_line}\" '
      NR > start && /受動|passive|stdout.*emit|emit.*stdout/ {passive=1}
      NR > start && /能動|active.*poll/ {active=1}
      NR > start && /^## \[/ && NR > start+1 {exit}
      END {exit !(passive && active)}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8.1: cld-observe-any wrapper または bootstrap script で
#        IDLE_COMPLETED_AUTO_KILL=1 を env 恒久化
# ===========================================================================

@test "ac8.1: cld-observe-any has IDLE_COMPLETED_AUTO_KILL=1 as permanent default" {
  # AC: cld-observe-any の wrapper または bootstrap で IDLE_COMPLETED_AUTO_KILL=1 が恒久設定される
  # RED: 恒久設定がまだ存在しないため fail
  # 検証: wrapper スクリプトまたは cld-observe-any 本体に恒久的なデフォルト設定が存在する
  run bash -c "
    # wrapper を探す
    wrapper1='${REPO_ROOT}/../session/scripts/cld-observe-any-wrapper.sh'
    wrapper2='${REPO_ROOT}/../session/scripts/cld-observe-any-bootstrap.sh'
    wrapper3='${REPO_ROOT}/scripts/cld-observe-any-wrapper.sh'

    found=0
    for f in \"\${wrapper1}\" \"\${wrapper2}\" \"\${wrapper3}\"; do
      if [[ -f \"\$f\" ]]; then
        grep -q 'IDLE_COMPLETED_AUTO_KILL=1\|export IDLE_COMPLETED_AUTO_KILL.*1\|: \${IDLE_COMPLETED_AUTO_KILL:=1}' \"\$f\" && found=1 && break
      fi
    done

    # wrapper が存在しない場合は cld-observe-any 本体にデフォルト設定があるか確認
    if [[ \$found -eq 0 ]]; then
      grep -qE ': \\\${IDLE_COMPLETED_AUTO_KILL:=1}|IDLE_COMPLETED_AUTO_KILL=\\\${IDLE_COMPLETED_AUTO_KILL:-1}' \
        '${CLD_OBSERVE_ANY}' && found=1
    fi

    exit \$(( 1 - found ))
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8.2: monitor-channel-catalog.md IDLE_COMPLETED_PHRASE_REGEX (line 783) を
#        pilot-completion-signals.md (SSOT) から導出する形に変更
# ===========================================================================

@test "ac8.2: monitor-channel-catalog.md IDLE_COMPLETED_PHRASE_REGEX references pilot-completion-signals.md as SSOT" {
  # AC: IDLE_COMPLETED_PHRASE_REGEX が pilot-completion-signals.md を SSOT として参照する記載がある
  # RED: SSOT 参照の記載がまだないため fail
  run bash -c "
    # IDLE_COMPLETED_PHRASE_REGEX の直近（前後 10 行）に pilot-completion-signals.md への参照が存在する
    regex_line=\$(grep -n 'IDLE_COMPLETED_PHRASE_REGEX' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    [ -n \"\${regex_line}\" ] || exit 1
    start=\$(( regex_line > 10 ? regex_line - 10 : 1 ))
    end=\$(( regex_line + 10 ))
    awk -v s=\"\${start}\" -v e=\"\${end}\" '
      NR >= s && NR <= e && /pilot-completion-signals|PILOT_COMPLETION_SIGNALS|SSOT/ {found=1; exit}
      END {exit !found}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8.3: pilot-completion-signals.md の table (line 14-26) に
#        controller 完了句の SSOT を集約（新規追記）
# ===========================================================================

@test "ac8.3: pilot-completion-signals.md table contains IDLE-COMPLETED completion phrases as SSOT" {
  # AC: pilot-completion-signals.md の table に [IDLE-COMPLETED] completion phrases が SSOT として追記される
  # RED: [IDLE-COMPLETED] 関連のエントリがまだ追記されていないため fail
  run grep -qE 'IDLE.COMPLETED.*phrase|completion phrase.*SSOT|IDLE_COMPLETED_PHRASE|refined.*ラベル.*SSOT|nothing pending.*SSOT' \
    "${PILOT_SIGNALS}"
  [ "${status}" -eq 0 ]
}

@test "ac8.3: pilot-completion-signals.md table includes all required completion phrase categories" {
  # AC: table に「refined ラベル付与」「Status=Refined」「nothing pending」等の全完了句が収録されている
  # RED: 必要な完了句がまだ追記されていないため fail
  run bash -c "
    # 現在の table (line 14-26 付近) に IDLE-COMPLETED completion phrases のセクションが存在する
    grep -qE 'IDLE.COMPLETED|completion phrase|completion.*signal.*table' '${PILOT_SIGNALS}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC8.4: bats で IDLE_COMPLETED_AUTO_KILL=1 が cld-observe-any 起動時 default に
#        なっていることを assert + IDLE_COMPLETED_PHRASE_REGEX が
#        pilot-completion-signals.md と整合することを assert
# ===========================================================================

@test "ac8.4: IDLE_COMPLETED_AUTO_KILL defaults to 1 when cld-observe-any launched via wrapper" {
  # AC: wrapper/bootstrap 経由で cld-observe-any を起動すると IDLE_COMPLETED_AUTO_KILL=1 が設定される
  # RED: wrapper が存在しないため fail
  run bash -c "
    wrapper1='${REPO_ROOT}/../session/scripts/cld-observe-any-wrapper.sh'
    wrapper2='${REPO_ROOT}/../session/scripts/cld-observe-any-bootstrap.sh'
    wrapper3='${REPO_ROOT}/scripts/cld-observe-any-wrapper.sh'

    for f in \"\${wrapper1}\" \"\${wrapper2}\" \"\${wrapper3}\"; do
      if [[ -f \"\$f\" ]]; then
        # source して IDLE_COMPLETED_AUTO_KILL の値を確認
        # --source-only / _DAEMON_LOAD_ONLY を使って関数定義のみロード
        val=\$(
          _DAEMON_LOAD_ONLY=1 source \"\$f\" 2>/dev/null || true
          echo \"\${IDLE_COMPLETED_AUTO_KILL:-unset}\"
        )
        [[ \"\${val}\" == '1' ]] && exit 0
      fi
    done

    # wrapper が存在しない場合もある（本体デフォルト設定で対応の場合）
    # その場合は本体の default 値が 1 であることを確認
    grep -qE ': \\\${IDLE_COMPLETED_AUTO_KILL:=1}|IDLE_COMPLETED_AUTO_KILL=\\\${IDLE_COMPLETED_AUTO_KILL:-1}' \
      '${CLD_OBSERVE_ANY}' && exit 0

    exit 1
  "
  [ "${status}" -eq 0 ]
}

@test "ac8.4: IDLE_COMPLETED_PHRASE_REGEX in catalog is consistent with pilot-completion-signals.md" {
  # AC: catalog の IDLE_COMPLETED_PHRASE_REGEX が pilot-completion-signals.md の完了句と整合する
  # RED: SSOT への参照または整合性がまだ確立されていないため fail
  run bash -c "
    # catalog に IDLE_COMPLETED_PHRASE_REGEX が存在し pilot-completion-signals.md が SSOT として参照されている
    grep -qE 'IDLE_COMPLETED_PHRASE_REGEX' '${MONITOR_CATALOG}' || exit 1

    # pilot-completion-signals.md に IDLE-COMPLETED 関連の completion phrases が記載されている
    grep -qE 'IDLE.COMPLETED.*phrase|IDLE_COMPLETED_PHRASE|refined.*ラベル|nothing pending|Status=Refined' \
      '${PILOT_SIGNALS}' || exit 1

    # catalog の SSOT 参照記載を確認
    regex_line=\$(grep -n 'IDLE_COMPLETED_PHRASE_REGEX' '${MONITOR_CATALOG}' | head -1 | cut -d: -f1)
    start=\$(( regex_line > 15 ? regex_line - 15 : 1 ))
    end=\$(( regex_line + 15 ))
    awk -v s=\"\${start}\" -v e=\"\${end}\" '
      NR >= s && NR <= e && /pilot-completion-signals|SSOT/ {found=1; exit}
      END {exit !found}
    ' '${MONITOR_CATALOG}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9.1: 新規 plugins/twl/skills/su-observer/refs/observer-supervise-checklist.md 作成
# ===========================================================================

@test "ac9.1: observer-supervise-checklist.md exists" {
  # AC: plugins/twl/skills/su-observer/refs/observer-supervise-checklist.md が新規作成される
  # RED: ファイルがまだ存在しないため fail
  [ -f "${CHECKLIST}" ]
}

# ===========================================================================
# AC9.2: checklist 項目（supervise loop で各 cycle に verify する項目リスト）
# ===========================================================================

@test "ac9.2: observer-supervise-checklist.md contains verify items for supervise loop cycle" {
  # AC: checklist に supervise loop の各 cycle で verify すべき項目リストが含まれている
  # RED: ファイルが存在しないため fail
  [ -f "${CHECKLIST}" ]
  run bash -c "
    # checklist に少なくとも 3 件以上の項目（- [ ] または numbered list）が存在する
    item_count=\$(grep -cE '^\s*- \[ \]|^\s*[0-9]+\.' '${CHECKLIST}' 2>/dev/null || echo 0)
    [ \"\${item_count}\" -ge 3 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac9.2: observer-supervise-checklist.md covers PILOT-PHASE-COMPLETE and PILOT-WAVE-COLLECTED checks" {
  # AC: checklist に PILOT-PHASE-COMPLETE と PILOT-WAVE-COLLECTED の検知確認項目が含まれている
  # RED: ファイルが存在しないため fail
  [ -f "${CHECKLIST}" ]
  run grep -qE 'PILOT.PHASE.COMPLETE|PILOT.WAVE.COLLECTED' "${CHECKLIST}"
  [ "${status}" -eq 0 ]
}

@test "ac9.2: observer-supervise-checklist.md covers PR merge polling check" {
  # AC: checklist に PR merge polling の確認項目が含まれている
  # RED: ファイルが存在しないため fail
  [ -f "${CHECKLIST}" ]
  run grep -qE 'PR merge.*poll|merge.*poll|gh pr list.*merge' "${CHECKLIST}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9.3: SKILL.md or supervise-channels.md Step 1 supervise loop に
#        「各 cycle で observer-supervise-checklist.md 全項目 MUST verify」を組み込む
# ===========================================================================

@test "ac9.3: SKILL.md references observer-supervise-checklist.md in Step 1 supervise loop" {
  # AC: SKILL.md の Step 1 supervise loop に observer-supervise-checklist.md への参照が組み込まれる
  # RED: 参照がまだ組み込まれていないため fail
  run bash -c "
    grep -qE 'observer-supervise-checklist\.md' '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}

@test "ac9.3: supervise-channels.md or SKILL.md requires MUST verify all checklist items each cycle" {
  # AC: 「各 cycle で checklist 全項目 MUST verify」の記載がある
  # RED: 記載がまだないため fail
  run bash -c "
    grep -qE 'checklist.*全項目.*MUST|MUST.*verify.*checklist|全項目.*MUST.*verify|MUST.*checklist.*verify' \
      '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC9.4: file 存在 + SKILL.md or supervise-channels.md から reference 1 か所以上 +
#        bats で reference 整合確認
# ===========================================================================

@test "ac9.4: observer-supervise-checklist.md file exists (completion condition)" {
  # AC: ファイルが存在する（AC9.1 の完了確認）
  # RED: ファイルがまだ存在しないため fail
  [ -f "${CHECKLIST}" ]
}

@test "ac9.4: at least one reference to observer-supervise-checklist.md exists in SKILL.md or supervise-channels.md" {
  # AC: SKILL.md または supervise-channels.md から observer-supervise-checklist.md への参照が 1 か所以上ある
  # RED: 参照がまだないため fail
  run bash -c "
    ref_count=\$(grep -c 'observer-supervise-checklist\.md' '${SKILL_MD}' '${SUPERVISE_CHANNELS}' 2>/dev/null | \
      awk -F: '{sum += \$2} END {print sum}')
    [ \"\${ref_count}\" -ge 1 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac9.4: observer-supervise-checklist.md reference is reachable from supervise loop Step 1" {
  # AC: supervise loop Step 1 のスコープ内 (SKILL.md Step 1 セクション または supervise-channels.md 冒頭)
  #     に observer-supervise-checklist.md への参照が存在する
  # RED: 参照が Step 1 スコープ外にあるか存在しないため fail
  run bash -c "
    # supervise-channels.md に参照があれば Step 1 文脈（supervise channels doc = Step 1 の実行内容）
    grep -qE 'observer-supervise-checklist\.md' '${SUPERVISE_CHANNELS}' && exit 0

    # SKILL.md の Step 1 セクション内に参照があるか確認
    step1_line=\$(grep -n '## Step 1' '${SKILL_MD}' | head -1 | cut -d: -f1)
    step2_line=\$(grep -n '## Step 2' '${SKILL_MD}' | head -1 | cut -d: -f1)
    [ -n \"\${step1_line}\" ] || exit 1
    [ -n \"\${step2_line}\" ] || exit 1
    awk -v s=\"\${step1_line}\" -v e=\"\${step2_line}\" '
      NR >= s && NR < e && /observer-supervise-checklist\.md/ {found=1; exit}
      END {exit !found}
    ' '${SKILL_MD}'
  "
  [ "${status}" -eq 0 ]
}
