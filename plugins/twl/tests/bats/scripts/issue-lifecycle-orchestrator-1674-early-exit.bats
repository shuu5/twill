#!/usr/bin/env bats
# issue-lifecycle-orchestrator-1674-early-exit.bats
# Issue #1674: bugfix: issue-lifecycle-orchestrator が reviewing→fixing 遷移後の
#              最初の inject (1/5) 直後に exit 0 で早期終了するバグ
#
# TDD RED フェーズ — 全テストは実装前に FAIL し、実装後に PASS する。
#
# AC coverage:
#   AC1 - wait_for_batch polling loop が batch 完了/timeout/explicit cancel 以外で break しない
#          静的検査: pane_state=$() への || true 保護なし → set -e silent fail リスクを検出
#   AC2 - set -e で trap EXIT を設置し、exit code と原因を state-log.jsonl に記録する
#   AC3a - 正常 case: STATE=fixing 遷移後の inject が inject_count < 5 の間は fallback しない
#   AC3b - 早期 break case: pane_state=$() が set -e リスクあるパターンを静的検出
#   AC3c - timeout case: MAX_POLL 超過で fallback 生成（既存挙動維持）を確認

load '../helpers/common'

SCRIPT_SRC=""
TMP_ORCH_DIR=""
ORCH_SCRIPTS_DIR=""
SESS_SCRIPTS_DIR=""

setup() {
  common_setup
  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"

  # orchestrator が SCRIPTS_ROOT/../../session/scripts/ を参照するため
  # ミラー構造を作成
  TMP_ORCH_DIR="$(mktemp -d)"
  ORCH_SCRIPTS_DIR="${TMP_ORCH_DIR}/plugins/twl/scripts"
  SESS_SCRIPTS_DIR="${TMP_ORCH_DIR}/plugins/session/scripts"
  mkdir -p "$ORCH_SCRIPTS_DIR" "$SESS_SCRIPTS_DIR"

  cp "$SCRIPT_SRC" "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh"
  chmod +x "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh"
}

teardown() {
  [[ -n "$TMP_ORCH_DIR" ]] && rm -rf "$TMP_ORCH_DIR"
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session-state.sh stub を作成する
# ---------------------------------------------------------------------------
_make_session_state_stub() {
  local state="$1"
  local exit_code="${2:-0}"
  cat > "${SESS_SCRIPTS_DIR}/session-state.sh" <<STUB
#!/usr/bin/env bash
echo "${state}"
exit ${exit_code}
STUB
  chmod +x "${SESS_SCRIPTS_DIR}/session-state.sh"
}

# session-state.sh が失敗（exit 1）を返す stub
_make_session_state_failing_stub() {
  cat > "${SESS_SCRIPTS_DIR}/session-state.sh" <<'STUB'
#!/usr/bin/env bash
# simulate: session-state.sh がウィンドウ消失等で exit 1 を返すケース
echo "error: window not found" >&2
exit 1
STUB
  chmod +x "${SESS_SCRIPTS_DIR}/session-state.sh"
}

_make_session_comm_stub() {
  local log_file="$1"
  cat > "${SESS_SCRIPTS_DIR}/session-comm.sh" <<STUB
#!/usr/bin/env bash
echo "SESSION_COMM_CALLED: \$*" >> "${log_file}"
exit 0
STUB
  chmod +x "${SESS_SCRIPTS_DIR}/session-comm.sh"
}

# ===========================================================================
# AC1: wait_for_batch polling loop が batch 完了/timeout/cancel 以外で break しない
# 静的検査: pane_state=$() に || true 保護がないパターン → set -e silent fail リスク
# ===========================================================================

# ---------------------------------------------------------------------------
# AC1-static1: pane_state=$(...) の代入行に || true 保護がない
# WHEN issue-lifecycle-orchestrator.sh の pane_state 代入行を確認する
# THEN 代入に || true が欠如している（現状のバグを static に検出）
# RED: 現在の L509 が || true なしのため、このテストは
#      "保護なし" を検出することで FAIL する（修正後は PASS）
#      正確には: 修正前は || true が存在しないため grep が fail → このテストは RED になる
# ---------------------------------------------------------------------------

@test "ac1: pane_state 代入に || true 保護がある (set -e silent fail を防ぐ)" {
  # AC1: set -e が有効な環境で pane_state=$(session-state.sh ...) が失敗した場合、
  #      || true または OR ガードがないとスクリプト全体が exit する。
  # 実装後: pane_state=$(...) || true または pane_state=$(...) || pane_state="" 形式で保護される
  # RED: 現在は保護なし → grep が 0 件 → fail
  grep -qE 'pane_state=\$\(.*session-state.*\).*\|\|' "$SCRIPT_SRC" \
    || fail "#1674 AC1 RED: pane_state=\$(session-state.sh ...) に || true 保護が存在しない。" \
            "set -e 環境で session-state.sh が exit 1 を返すと、orchestrator が silent に early exit する。" \
            "修正: pane_state=\$(... 2>/dev/null) || true を追加すること。"
}

@test "ac1: _pre_inject_state 代入にも || true 保護がある (set -e silent fail を防ぐ)" {
  # AC1: 同じリスクが _pre_inject_state=$() にも存在する（L570）
  # 実装後: _pre_inject_state=$(...) || true 形式で保護される
  # RED: 現在は保護なし → fail
  grep -qE '_pre_inject_state=\$\(.*session-state.*\).*\|\|' "$SCRIPT_SRC" \
    || fail "#1674 AC1 RED: _pre_inject_state=\$(session-state.sh ...) に || true 保護が存在しない。" \
            "set -e 環境で session-state.sh が exit 1 を返すと、orchestrator が silent に early exit する。"
}

@test "ac1: wait_for_batch の break 条件が 3 種類（all_done/poll_limit/explicit_cancel）のみである" {
  # AC1: wait_for_batch polling loop の break は以下のみであること
  #      - all_done=true（全 subdir 完了）
  #      - poll_count >= MAX_POLL（タイムアウト）
  #      - explicit cancel（まだ未実装）
  # 実装後: pane_state=$() 失敗時でも all_done=false で継続する
  # この静的テストは: set -e guard を確認する（pane_state 代入に保護がある → break しない）
  local wait_region
  wait_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")

  # pane_state 代入が || true で保護されているか、または local + separate assignment で保護されているか
  local protected
  protected=$(printf '%s' "$wait_region" | grep -E 'pane_state=\$\(.*\).*\|\|' | head -1)

  [[ -n "$protected" ]] \
    || fail "#1674 AC1 RED: wait_for_batch 内の pane_state=\$(...) が set -e リスクから保護されていない。" \
            "session-state.sh が失敗した場合 (exit 1)、set -e により polling loop が早期終了する。"
}

# ===========================================================================
# AC2: set -e で trap EXIT を設置し、exit code と原因を state-log.jsonl に記録する
# ===========================================================================

# ---------------------------------------------------------------------------
# AC2-static1: EXIT trap が state-log.jsonl への書き込みを含む
# WHEN issue-lifecycle-orchestrator.sh を確認する
# THEN trap EXIT ハンドラが state-log.jsonl への記録を行う
# RED: 現在は lockfile cleanup のみの trap → fail
# ---------------------------------------------------------------------------

@test "ac2: EXIT trap が state-log.jsonl への記録を含む" {
  # AC2: set -e による early exit を trap し、audit log に記録する
  # 現在の trap (L31): 'rm -f /tmp/.coi-window-*.lock 2>/dev/null || true'
  # 実装後: trap ハンドラが state-log.jsonl に exit code と原因を記録する
  # RED: 現在は state-log.jsonl が trap に存在しない → fail
  grep -qE 'state-log\.jsonl' "$SCRIPT_SRC" \
    || fail "#1674 AC2 RED: EXIT trap が state-log.jsonl への記録を含まない。" \
            "現在の trap は lockfile cleanup のみ (L31)。" \
            "実装後: trap ハンドラで exit code と原因を .audit/auto-<run_id>-issue-<N>/state-log.jsonl に記録すること。"
}

@test "ac2: EXIT trap が exit code を記録する（\$? の保存がある）" {
  # AC2: trap ハンドラが終了直前の exit code を記録するために $? を保存する
  # 実装後: _exit_code=$? を trap の冒頭で保存 → jsonl に記録
  # RED: 現在は exit code の保存ロジックが trap に存在しない → fail
  local trap_context
  trap_context=$(grep -A 10 "^trap '" "$SCRIPT_SRC" | head -15)
  printf '%s' "$trap_context" | grep -qE '_exit_code=\$\?|exit_code=\$\?' \
    || fail "#1674 AC2 RED: trap EXIT ハンドラが exit code (\$?) を保存していない。" \
            "set -e による early exit 時の exit code を記録するため、trap 冒頭で '_exit_code=\$?' が必要。"
}

@test "ac2: .audit ディレクトリパスがスクリプトに存在する" {
  # AC2: audit log の書き込み先は .audit/auto-{run_id}-issue-{N}/state-log.jsonl
  # 実装後: .audit パスの構築ロジックが存在する
  # RED: 現在は .audit/ パスが存在しない → fail
  grep -qE '\.audit/' "$SCRIPT_SRC" \
    || fail "#1674 AC2 RED: .audit/ ディレクトリパスがスクリプトに存在しない。" \
            "audit log の書き込み先: .audit/auto-{run_id}-issue-{N}/state-log.jsonl"
}

@test "ac2: run_id がスクリプト内で生成/使用される" {
  # AC2: audit log のパスに使う run_id が生成される
  # 実装後: run_id=$(uuidgen) または date ベースの ID が先頭で設定される
  # RED: 現在は run_id という変数が存在しない → fail
  grep -qE 'run_id' "$SCRIPT_SRC" \
    || fail "#1674 AC2 RED: run_id 変数がスクリプトに存在しない。" \
            "audit log パス (.audit/auto-{run_id}-issue-{N}/) に使う run_id が必要。"
}

# ===========================================================================
# AC3a: 正常 case — STATE=fixing 遷移後の inject が inject_count < 5 の間は fallback しない
# ===========================================================================

# ---------------------------------------------------------------------------
# AC3a-static1: inject_count < 5 の間は fixing inject ロジックが fallback を呼ばない
# WHEN issue-lifecycle-orchestrator.sh の fixing inject ブロックを確認する
# THEN inject_count < 5 のパスが _generate_fallback_report を呼ばない
# GREEN: 現状のコードで静的確認 → 既存動作確認テスト
# （このテストは実装前から PASS するか確認が必要）
# ---------------------------------------------------------------------------

@test "ac3a: STATE=fixing inject ブロックが inject_count < 5 で fallback を呼ばない (静的確認)" {
  # AC3a: fixing inject ブロック（elif current_state == fixing ）は
  #       inject_count をインクリメントして inject するのみ
  #       inject_count >= 5 の場合のみ fallback が呼ばれる（inject 5 回上限ロジック）
  # この静的確認: fixing inject ブロック内に _generate_fallback_report がないこと
  local fixing_line end_line fallback_in_fixing
  fixing_line=$(grep -n '"fixing"' "$SCRIPT_SRC" | grep -v "^[0-9]*:[[:space:]]*#" | head -1 | cut -d: -f1)
  [[ -n "$fixing_line" ]] \
    || fail "#1674 AC3a: fixing 条件がスクリプトに存在しない（STATE-aware inject 未実装）"

  # fixing ブロックの終わり（else ブロック開始前）を推定（最大 30 行）
  end_line=$((fixing_line + 30))
  fallback_in_fixing=$(awk "NR>=$fixing_line && NR<=$end_line && /_generate_fallback_report/" "$SCRIPT_SRC" | head -1)
  [[ -z "$fallback_in_fixing" ]] \
    || fail "#1674 AC3a: fixing inject ブロック内（L${fixing_line}〜${end_line}）に _generate_fallback_report が存在する。" \
            "inject_count < 5 のパスで fallback が呼ばれている可能性がある。"
}

@test "ac3a: fixing inject 後に all_done=false が設定される (loop 継続が保証される)" {
  # AC3a: inject した後に all_done=false を設定して polling loop を継続させることを確認
  # set -e で early exit した場合はこの行に到達しない
  # RED: pane_state=$() が || true なしで失敗すると all_done=false に到達しない → このテストが示す問題
  local fixing_region
  fixing_region=$(awk '/elif.*fixing/{f=1} f{print; if(/all_done=false/) {found=1} if(found && /^\s*$/) exit}' "$SCRIPT_SRC" | head -20)
  printf '%s' "$fixing_region" | grep -qE 'all_done=false' \
    || fail "#1674 AC3a: fixing inject ブロック後に all_done=false が設定されていない。" \
            "inject 後は必ず all_done=false で loop を継続させること。"
}

# ---------------------------------------------------------------------------
# AC3a-runtime: STATE=fixing で inject_count=1 の subdir がある場合、
#               orchestrator が早期 exit しないことを確認する (runtime テスト)
#
# 構成:
#   - subdir 1つ: IN/draft.md あり、OUT/report.json なし
#   - STATE ファイル: fixing
#   - .inject_count: 1 （inject 1 回済み、まだ 4 回残っている）
#   - session-state.sh stub: "input-waiting" を返す
#   - MAX_POLL=2 で polling → タイムアウト fallback が発生（report.json が生成される）
#   - exit code: 0 でも 1 でもよい（早期 exit 0 ではなく正常完了 OR タイムアウトであること）
#
# 早期 exit 判定: MAX_POLL=2 で 2 回ポーリングが行われれば OK
# (early exit の場合はポーリングが 0〜1 回しか行われない)
# ---------------------------------------------------------------------------

@test "ac3a: STATE=fixing + inject_count=1 で MAX_POLL=2 まで polling が継続する" {
  # AC3a runtime: reviewing→fixing 遷移後の 1/5 inject 直後に early exit しないことを確認
  # set -e + || true なし の場合: session-state.sh が exit 0 でも
  # 内部での他のコマンド失敗で early exit する可能性
  # このテストは: MAX_POLL=2 を設定し、poll_count が 2 回に達することを確認する
  # （early exit の場合は poll が 1 回にとどまり、report.json が timeout ではない理由で生成される）

  local per_issue_dir="${TMP_ORCH_DIR}/per-issue"
  local subdir="${per_issue_dir}/issue-001"
  mkdir -p "${subdir}/IN" "${subdir}/OUT"
  printf 'test draft content\n' > "${subdir}/IN/draft.md"

  # STATE=fixing を設定
  printf 'fixing\n' > "${subdir}/STATE"
  # inject_count=1（1 回 inject 済み）
  printf '1\n' > "${subdir}/.inject_count"
  # .debounce_ts を設定（debounce 通過済みにする）
  printf '%s\n' "$(( $(date +%s) - 200 ))" > "${subdir}/.debounce_ts"

  # .unclassified_debounce_ts を設定（unclassified debounce 通過済み）
  printf '%s\n' "$(( $(date +%s) - 60 ))" > "${subdir}/.unclassified_debounce_ts"

  # session-state.sh stub: 常に input-waiting を返す
  _make_session_state_stub "input-waiting" 0

  # session-comm.sh stub: inject を記録する
  local inject_log="${TMP_ORCH_DIR}/inject.log"
  _make_session_comm_stub "$inject_log"

  # lib/llm-indicators.sh stub
  mkdir -p "${ORCH_SCRIPTS_DIR}/../../session/scripts/lib"
  cp "${SESS_SCRIPTS_DIR}/session-state.sh" "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-state.sh" 2>/dev/null || true
  cp "${SESS_SCRIPTS_DIR}/session-comm.sh" "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-comm.sh" 2>/dev/null || true

  local sid8
  sid8="$(basename "$TMP_ORCH_DIR" | cut -c1-8 | tr -c 'a-zA-Z0-9_-' 'x')"

  # tmux stub: window は存在し、capture-pane は classify できないテキストを返す
  stub_command "tmux" "
    case \"\$1\" in
      list-windows)
        printf 'coi-${sid8}-0\n'
        ;;
      capture-pane)
        printf 'Processing...\n'
        ;;
      kill-window|set-option) exit 0 ;;
      *) exit 0 ;;
    esac
  "

  # cld stub
  stub_command "cld" 'exit 0'

  # MAX_POLL=2, POLL_INTERVAL=0, DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC=0 で実行
  # STARTUP_GRACE_PERIOD=0 で grace period を無効化
  STARTUP_GRACE_PERIOD=0 \
  DEBOUNCE_TRANSIENT_SEC=0 \
  DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC=0 \
  MAX_POLL=2 POLL_INTERVAL=0 \
    run bash "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "$per_issue_dir"

  # exit code はタイムアウト（OVERALL_FAILED > 0 で exit 1）でもよい
  # 重要: report.json が生成されていること（タイムアウトまで polling が継続したことを示す）
  [[ -f "${subdir}/OUT/report.json" ]] \
    || fail "#1674 AC3a: STATE=fixing + inject_count=1 の場合、MAX_POLL=2 polling が完了する前に" \
            "early exit した（OUT/report.json が生成されていない）。" \
            "set -e + || true なしの pane_state=\$() が early exit の原因の可能性。"
}

# ===========================================================================
# AC3b: 早期 break case — set -e が silent fail を引き起こしうるコマンドの静的検出
# ===========================================================================

# ---------------------------------------------------------------------------
# AC3b-static1: wait_for_batch 内の command substitution が || true 保護を持つ
# WHEN wait_for_batch 関数内を grep する
# THEN var=$(...) 形式の代入が || true なしで存在するパターンを検出する
# RED: 現在は pane_state=$() と _pre_inject_state=$() に保護なし → fail
# ---------------------------------------------------------------------------

@test "ac3b: wait_for_batch 内のコマンド置換代入が || true 保護を持つ (set -e リスク排除)" {
  # AC3b: wait_for_batch 内で変数に command substitution を代入する箇所を全て確認
  # session-state.sh への呼び出し: pane_state=$() と _pre_inject_state=$()
  # これらが || true なしの場合、session-state.sh exit 1 → set -e → early exit
  local wait_region
  wait_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")

  # session-state.sh 呼び出しを含む代入行を抽出
  local unprotected
  unprotected=$(printf '%s' "$wait_region" \
    | grep -E '[a-z_]+=\$\(.*session-state' \
    | grep -vE '\|\|' \
    | head -5)

  [[ -z "$unprotected" ]] \
    || fail "#1674 AC3b: wait_for_batch 内に || true 保護なしの session-state.sh 代入が存在する:" \
            "$unprotected" \
            "set -e 環境で session-state.sh が exit 1 を返すと silent early exit が発生する。"
}

@test "ac3b: session-state.sh が exit 1 を返してもスクリプトが継続する (set -e 耐性)" {
  # AC3b runtime: session-state.sh が失敗（exit 1）しても early exit しないことを確認
  # 修正前: pane_state=$(session-state.sh state ...) が exit 1 → set -e → early exit
  # 修正後: pane_state=$(... 2>/dev/null) || true → exit 1 を吸収して継続

  local per_issue_dir="${TMP_ORCH_DIR}/per-issue-sete"
  local subdir="${per_issue_dir}/issue-002"
  mkdir -p "${subdir}/IN" "${subdir}/OUT"
  printf 'test draft\n' > "${subdir}/IN/draft.md"

  # .debounce_ts を grace period 後に設定（pane_state チェックに到達させる）
  printf '%s\n' "$(( $(date +%s) - 200 ))" > "${subdir}/.debounce_ts"

  # session-state.sh stub: exit 1 を返す（失敗ケース）
  _make_session_state_failing_stub

  # session-comm.sh stub
  local inject_log2="${TMP_ORCH_DIR}/inject2.log"
  _make_session_comm_stub "$inject_log2"

  # orchestrator の SCRIPTS_ROOT 配下にパス解決されるよう session-state.sh を設置
  mkdir -p "${ORCH_SCRIPTS_DIR}/../../session/scripts"
  cp "${SESS_SCRIPTS_DIR}/session-state.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-state.sh" 2>/dev/null || true
  cp "${SESS_SCRIPTS_DIR}/session-comm.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-comm.sh" 2>/dev/null || true

  local sid8b
  sid8b="$(basename "$TMP_ORCH_DIR" | cut -c1-8 | tr -c 'a-zA-Z0-9_-' 'x')"

  stub_command "tmux" "
    case \"\$1\" in
      list-windows) printf 'coi-${sid8b}-0\n' ;;
      capture-pane) printf 'Idle...\n' ;;
      kill-window|set-option) exit 0 ;;
      *) exit 0 ;;
    esac
  "
  stub_command "cld" 'exit 0'

  # STARTUP_GRACE_PERIOD=0, MAX_POLL=1 で実行
  # session-state.sh が exit 1 → 保護なしなら early exit → report.json なし
  # 保護ありなら MAX_POLL=1 タイムアウト → report.json 生成
  STARTUP_GRACE_PERIOD=0 \
  DEBOUNCE_TRANSIENT_SEC=0 \
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "$per_issue_dir"

  # 修正後の期待: report.json が存在する（タイムアウトまで polling が完了した）
  [[ -f "${subdir}/OUT/report.json" ]] \
    || fail "#1674 AC3b: session-state.sh が exit 1 を返したとき、" \
            "set -e により orchestrator が early exit した（OUT/report.json が生成されていない）。" \
            "修正: pane_state=\$(... 2>/dev/null) || true を追加すること。"
}

# ===========================================================================
# AC3c: timeout case — MAX_POLL 超過でフォールバック生成（既存挙動維持）
# ===========================================================================

# ---------------------------------------------------------------------------
# AC3c: MAX_POLL 超過で fallback report.json が生成される（リグレッション防止）
# WHEN subdir が IN/draft.md を持ち OUT/report.json を持たない
# AND MAX_POLL=1 POLL_INTERVAL=0 で実行する
# THEN OUT/report.json が {"status":"timeout"} で生成される
# ---------------------------------------------------------------------------

@test "ac3c: MAX_POLL 超過で timeout fallback report.json が生成される (既存挙動維持)" {
  # AC3c: 既存の timeout 挙動が維持されることを確認（リグレッション防止）
  local per_issue_dir="${TMP_ORCH_DIR}/per-issue-timeout"
  local subdir="${per_issue_dir}/issue-003"
  mkdir -p "${subdir}/IN"
  printf 'test draft\n' > "${subdir}/IN/draft.md"

  # session-state.sh stub: 非 input-waiting を返す（debounce をスキップ）
  _make_session_state_stub "running" 0

  local inject_log3="${TMP_ORCH_DIR}/inject3.log"
  _make_session_comm_stub "$inject_log3"

  mkdir -p "${ORCH_SCRIPTS_DIR}/../../session/scripts"
  cp "${SESS_SCRIPTS_DIR}/session-state.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-state.sh" 2>/dev/null || true
  cp "${SESS_SCRIPTS_DIR}/session-comm.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-comm.sh" 2>/dev/null || true

  local sid8c
  sid8c="$(basename "$TMP_ORCH_DIR" | cut -c1-8 | tr -c 'a-zA-Z0-9_-' 'x')"

  stub_command "tmux" "
    case \"\$1\" in
      list-windows) printf 'coi-${sid8c}-0\n' ;;
      capture-pane) printf 'Running...\n' ;;
      kill-window|set-option) exit 0 ;;
      *) exit 0 ;;
    esac
  "
  stub_command "cld" 'exit 0'

  STARTUP_GRACE_PERIOD=0 \
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "$per_issue_dir"

  # タイムアウトで report.json が生成されること
  [[ -f "${subdir}/OUT/report.json" ]] \
    || fail "#1674 AC3c: MAX_POLL=1 タイムアウトで OUT/report.json が生成されなかった。"

  # report.json の status が "timeout" であること
  local timeout_status
  timeout_status=$(python3 -c "import json; d=json.load(open('${subdir}/OUT/report.json')); print(d.get('status',''))" 2>/dev/null || echo "")
  [[ "$timeout_status" == "timeout" ]] \
    || fail "#1674 AC3c: タイムアウト report.json の status が 'timeout' でない (got: $timeout_status)"
}

@test "ac3c: タイムアウト後の exit code が非ゼロである (OVERALL_FAILED > 0)" {
  # AC3c: タイムアウトした場合は OVERALL_FAILED が 1 以上 → exit 1
  # （タイムアウトは success ではなく failure として扱われる）
  local per_issue_dir="${TMP_ORCH_DIR}/per-issue-timeout2"
  local subdir="${per_issue_dir}/issue-004"
  mkdir -p "${subdir}/IN"
  printf 'test draft\n' > "${subdir}/IN/draft.md"

  _make_session_state_stub "running" 0
  local inject_log4="${TMP_ORCH_DIR}/inject4.log"
  _make_session_comm_stub "$inject_log4"

  mkdir -p "${ORCH_SCRIPTS_DIR}/../../session/scripts"
  cp "${SESS_SCRIPTS_DIR}/session-state.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-state.sh" 2>/dev/null || true
  cp "${SESS_SCRIPTS_DIR}/session-comm.sh" \
    "${ORCH_SCRIPTS_DIR}/../../session/scripts/session-comm.sh" 2>/dev/null || true

  local sid8d
  sid8d="$(basename "$TMP_ORCH_DIR" | cut -c1-8 | tr -c 'a-zA-Z0-9_-' 'x')"

  stub_command "tmux" "
    case \"\$1\" in
      list-windows) printf 'coi-${sid8d}-0\n' ;;
      capture-pane) printf 'Running...\n' ;;
      kill-window|set-option) exit 0 ;;
      *) exit 0 ;;
    esac
  "
  stub_command "cld" 'exit 0'

  STARTUP_GRACE_PERIOD=0 \
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "${ORCH_SCRIPTS_DIR}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "$per_issue_dir"

  # タイムアウト（status=timeout）は OVERALL_FAILED > 0 → exit 1
  [[ "$status" -ne 0 ]] \
    || fail "#1674 AC3c: タイムアウト時に exit 0 が返された。タイムアウトは failure として exit 1 であるべき。"
}

# ===========================================================================
# 追加: fixing inject が inject_count を正しくインクリメントする静的確認
# ===========================================================================

@test "ac3-count: fixing inject が inject_count をインクリメントする (fallback しない)" {
  # reviewing → fixing 遷移後の inject 1/5 以降の処理:
  # inject_count をインクリメント → all_done=false → loop 継続
  # が実装されていることを静的に確認
  local fixing_line fixing_block
  fixing_line=$(grep -n '"fixing"' "$SCRIPT_SRC" | grep -v "^[0-9]*:[[:space:]]*#" | head -1 | cut -d: -f1)
  [[ -n "$fixing_line" ]] \
    || fail "#1674: STATE=fixing 条件がスクリプトに存在しない"

  fixing_block=$(awk "NR>=$fixing_line && NR<=$((fixing_line + 20))" "$SCRIPT_SRC")

  # inject_count インクリメントが存在する
  printf '%s' "$fixing_block" | grep -qE 'inject_count=\$\(\(inject_count.*\+.*1\)\)|inject_count\+\+' \
    || fail "#1674: fixing inject ブロック内に inject_count インクリメントが存在しない"

  # all_done=false が存在する（loop 継続）
  printf '%s' "$fixing_block" | grep -qE 'all_done=false' \
    || fail "#1674: fixing inject ブロック後に all_done=false が存在しない（loop 継続保証なし）"
}
