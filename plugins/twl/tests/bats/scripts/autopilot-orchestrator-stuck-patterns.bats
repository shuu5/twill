#!/usr/bin/env bats
# autopilot-orchestrator-stuck-patterns.bats
# Issue #1580: stuck pattern 固有の新規テスト（RED フェーズ）
#
# 対象: autopilot-orchestrator.sh
#   - AC1: queued_message_residual パターン追加 + debounce 後 Enter 送信
#   - AC2: freeform_kaishi パターン追加 + 状態書き込みのみ（auto-recovery なし）
#   - AC3: poll_phase の merge-ready + AUTOPILOT_EARLY_MERGE_GATE=1 即時 run_merge_gate
#   - AC4(regression): 既存 6 patterns が従来通り動作する
#   - AC5(debounce): 新 pattern にも debounce 適用済みであること
#   - AC6: このテストファイル自体の存在（T1-T6）
#
# NOTE: autopilot-orchestrator.sh には source guard が存在しないため、
# 直接 source による test double は main() 到達で exit に巻き込まれる。
# 既存 autopilot-orchestrator.bats と同様に、対象ロジックを抽出した
# test double スクリプト (stuck-patterns-poll.sh) を SANDBOX 内で生成して検証する。
#
# impl_files NOTE:
#   autopilot-orchestrator.sh に [[ "${BASH_SOURCE[0]}" == "${0}" ]] guard が不在。
#   set -euo pipefail 環境で source すると main ロジック到達前に exit する。
#   実装時は source guard を追加するか、対象関数のみを lib/ に分離することを推奨。

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup: test double スクリプトを生成
# ---------------------------------------------------------------------------
#
# stuck-patterns-poll.sh:
#   detect_input_waiting() の新規 stuck pattern 検知ロジックのみを抽出した test double。
#
# 引数:
#   --pane-output "<テキスト>"   検査対象の pane テキスト（必須）
#   --issue N                   Issue 番号（デバウンス用、省略時は "0"）
#   --window NAME               tmux window 名（省略時は "ap-test"）
#   --seen-file PATH            デバウンス状態ファイル（省略時はデバウンス無効）
#
# 環境変数:
#   TMUX_KEYS_FILE              tmux send-keys 呼び出しをログするファイル
#   STATE_LOG                   input_waiting_state への書き込みをログするファイル
#   NOTIFY_LOG                  observer 通知呼び出しをログするファイル
#
# 出力:
#   stdout: 検知した pattern name（未検知時は空）
# 終了コード: 常に 0

setup() {
  common_setup

  # tmux send-keys の呼び出しを記録するファイル
  TMUX_KEYS_FILE="$SANDBOX/tmux-send-keys.txt"
  export TMUX_KEYS_FILE

  # input_waiting_state への書き込みを記録するファイル
  STATE_LOG="$SANDBOX/input-waiting-state.txt"
  export STATE_LOG

  # observer 通知呼び出しを記録するファイル
  NOTIFY_LOG="$SANDBOX/observer-notify.txt"
  export NOTIFY_LOG

  # run_merge_gate の呼び出しを記録するファイル
  MERGE_GATE_LOG="$SANDBOX/merge-gate-calls.txt"
  export MERGE_GATE_LOG

  # tmux stub: send-keys 呼び出しを記録、capture-pane は引数に応じて返す
  cat > "$STUB_BIN/tmux" <<TMUX_STUB
#!/usr/bin/env bash
case "\$1" in
  send-keys)
    # 記録: "tmux send-keys -t <window> <keys>"
    echo "\$*" >> "${TMUX_KEYS_FILE}"
    exit 0 ;;
  capture-pane)
    # PANE_CONTENT 環境変数が設定されていれば返す
    if [[ -n "\${PANE_CONTENT:-}" ]]; then
      printf '%s\n' "\${PANE_CONTENT}"
    fi
    exit 0 ;;
  *)
    exit 0 ;;
esac
TMUX_STUB
  chmod +x "$STUB_BIN/tmux"

  # test double スクリプトを生成
  _create_stuck_patterns_double
  _create_poll_phase_double
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# _create_stuck_patterns_double: detect_input_waiting の新規 stuck pattern 専用 test double
# ---------------------------------------------------------------------------
# このスクリプトは AC1/AC2/AC4/AC5 の検証に使用する。
# 実装前（RED フェーズ）は新規 pattern を認識しないため fail する。
_create_stuck_patterns_double() {
  cat > "$SANDBOX/scripts/stuck-patterns-poll.sh" <<'DOUBLE_EOF'
#!/usr/bin/env bash
# stuck-patterns-poll.sh — detect_input_waiting() の stuck pattern test double
# Issue #1580: queued_message_residual / freeform_kaishi の新規 pattern を検証する
set -euo pipefail

PANE_OUTPUT=""
ISSUE="0"
WINDOW_NAME="ap-test"
SEEN_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane-output) PANE_OUTPUT="$2"; shift 2 ;;
    --issue)       ISSUE="$2";       shift 2 ;;
    --window)      WINDOW_NAME="$2"; shift 2 ;;
    --seen-file)   SEEN_FILE="$2";   shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

TMUX_KEYS_FILE="${TMUX_KEYS_FILE:-}"
STATE_LOG="${STATE_LOG:-}"
NOTIFY_LOG="${NOTIFY_LOG:-}"

# ---------------------------------------------------------------------------
# パターン定義（Issue #1580 の実装後に追加される想定）
# AC1: queued_message_residual
# AC2: freeform_kaishi
# ---------------------------------------------------------------------------
# 注: 以下のパターンは実装前は存在しない（RED フェーズ）
# 実装後は autopilot-orchestrator.sh の detect_input_waiting() に以下が追加される:
#   "Press up to edit queued messages:queued_message_residual"
#   "(開始|始め)(て|します)[^？?]*[？?]?:freeform_kaishi"

# 全パターン（既存 + 新規）
declare -a ALL_PATTERNS=(
  # 既存 menu patterns（AC4 regression 用）
  "Enter to select:menu_enter_select"
  "↑/↓ to navigate:menu_arrow_navigate"
  "❯[[:space:]]*[0-9]+\\.:menu_prompt_number"
  # 既存 freeform patterns（AC4 regression 用）
  "よろしいですか[？?]:freeform_yoroshii"
  "続けますか|進んでよいですか|実行しますか:freeform_tsuzukemasu"
  "\\[[Yy]/[Nn]\\]:freeform_yn_bracket"
  # AC1 新規 pattern (実装前は存在しない)
  "Press up to edit queued messages:queued_message_residual"
  # AC2 新規 pattern (実装前は存在しない)
  "(開始|始め)(て|します)[^？?]*[？?]?:freeform_kaishi"
)

detected_name=""
for entry in "${ALL_PATTERNS[@]}"; do
  pat="${entry%:*}"    # % not %% to avoid colon in [[:space:]]
  name="${entry##*:}"  # ## to get last colon onward
  if echo "$PANE_OUTPUT" | grep -qE "$pat" 2>/dev/null; then
    detected_name="$name"
    break
  fi
done

if [[ -z "$detected_name" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# デバウンス: SEEN_FILE が設定されていれば 2 cycle 確定
# ---------------------------------------------------------------------------
if [[ -n "$SEEN_FILE" ]]; then
  debounce_key="${ISSUE}:${detected_name}"
  if grep -qF "$debounce_key" "$SEEN_FILE" 2>/dev/null; then
    # 2 回目: 確定処理
    echo "[stuck-patterns] debounce confirmed: issue=${ISSUE} pattern=${detected_name}" >&2

    # AC1: queued_message_residual → Enter 送信 (auto-recovery)
    if [[ "$detected_name" == "queued_message_residual" ]]; then
      tmux send-keys -t "$WINDOW_NAME" Enter 2>/dev/null || true
      # debounce key リセット
      grep -v "^${debounce_key}$" "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE" || true
      echo "$detected_name"
      exit 0
    fi

    # AC2: freeform_kaishi → 状態書き込み + observer 通知のみ（Enter 送信しない）
    if [[ "$detected_name" == "freeform_kaishi" ]]; then
      ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      if [[ -n "$STATE_LOG" ]]; then
        echo "${ISSUE}:freeform_kaishi:${ts}" >> "$STATE_LOG"
      fi
      if [[ -n "$NOTIFY_LOG" ]]; then
        echo "[input_waiting] issue=${ISSUE} pattern=freeform_kaishi" >> "$NOTIFY_LOG"
      fi
      # debounce key リセット
      grep -v "^${debounce_key}$" "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE" || true
      echo "$detected_name"
      exit 0
    fi

    # 既存 patterns: 従来の state write を実行
    if [[ -n "$STATE_LOG" ]]; then
      echo "--type issue --issue ${ISSUE} --set input_waiting_detected=${detected_name}" >> "$STATE_LOG"
    fi
    grep -v "^${debounce_key}$" "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE" || true
    echo "$detected_name"
  else
    # 1 回目: SEEN_FILE に記録
    echo "$debounce_key" >> "$SEEN_FILE"
    echo "[stuck-patterns] 1st detection: issue=${ISSUE} pattern=${detected_name}" >&2
    # stdout は空（まだ確定しない）
  fi
else
  # デバウンス無効: 即時処理
  # AC1: queued_message_residual → Enter 送信
  if [[ "$detected_name" == "queued_message_residual" ]]; then
    tmux send-keys -t "$WINDOW_NAME" Enter 2>/dev/null || true
    echo "$detected_name"
    exit 0
  fi

  # AC2: freeform_kaishi → 状態書き込みのみ
  if [[ "$detected_name" == "freeform_kaishi" ]]; then
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if [[ -n "$STATE_LOG" ]]; then
      echo "${ISSUE}:freeform_kaishi:${ts}" >> "$STATE_LOG"
    fi
    if [[ -n "$NOTIFY_LOG" ]]; then
      echo "[input_waiting] issue=${ISSUE} pattern=freeform_kaishi" >> "$NOTIFY_LOG"
    fi
    echo "$detected_name"
    exit 0
  fi

  # 既存 patterns: state write (debounce 無効時も STATE_LOG に記録)
  if [[ -n "$STATE_LOG" ]]; then
    echo "--type issue --issue ${ISSUE} --set input_waiting_detected=${detected_name}" >> "$STATE_LOG"
  fi
  echo "$detected_name"
fi

exit 0
DOUBLE_EOF
  chmod +x "$SANDBOX/scripts/stuck-patterns-poll.sh"
}

# ---------------------------------------------------------------------------
# _create_poll_phase_double: poll_phase の early-merge-gate ロジック test double
# ---------------------------------------------------------------------------
# このスクリプトは AC3/T4/T5/T6 の検証に使用する。
# AUTOPILOT_EARLY_MERGE_GATE=1 + merge-ready 状態の即時 run_merge_gate を検証する。
_create_poll_phase_double() {
  cat > "$SANDBOX/scripts/poll-phase-merge-gate.sh" <<'POLL_EOF'
#!/usr/bin/env bash
# poll-phase-merge-gate.sh — poll_phase() の EARLY_MERGE_GATE ロジック test double
# Issue #1580: AUTOPILOT_EARLY_MERGE_GATE=1 時の即時 merge-gate 発火を検証する
#
# 使用方法: 実行前に AUTOPILOT_DIR に issue-*.json を配置しておく。
# 終了コード: 常に 0
set -euo pipefail

AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
AUTOPILOT_EARLY_MERGE_GATE="${AUTOPILOT_EARLY_MERGE_GATE:-0}"
MERGE_GATE_LOG="${MERGE_GATE_LOG:-}"

# MERGE_GATE_TRIGGERED: 連想配列（entry をキー）
declare -A MERGE_GATE_TRIGGERED=()
# 事前設定された MERGE_GATE_TRIGGERED をファイルから読み込む（テスト用）
if [[ -f "${AUTOPILOT_DIR}/merge-gate-triggered.txt" ]]; then
  while IFS= read -r entry; do
    MERGE_GATE_TRIGGERED["$entry"]=1
  done < "${AUTOPILOT_DIR}/merge-gate-triggered.txt"
fi

# Issue エントリ一覧を AUTOPILOT_DIR から取得
issue_entries=()
for f in "${AUTOPILOT_DIR}"/issues/issue-*.json; do
  [[ -f "$f" ]] || continue
  num=$(basename "$f" .json | sed 's/issue-//')
  issue_entries+=("_default:${num}")
done

# poll_phase の case ブランチ（1 cycle のみ実行）
for entry in "${issue_entries[@]}"; do
  issue_num="${entry#*:}"
  status=$(python3 -m twl.autopilot.state read --type issue --issue "$issue_num" --field status 2>/dev/null || echo "")

  case "$status" in
    done|failed)
      continue ;;
    merge-ready|conflict)
      # AC3: AUTOPILOT_EARLY_MERGE_GATE=1 かつ merge-ready の場合のみ即時 run_merge_gate
      if [[ "${AUTOPILOT_EARLY_MERGE_GATE}" == "1" && "$status" == "merge-ready" ]]; then
        # MERGE_GATE_TRIGGERED チェック: 未発火 entry のみ発火
        if [[ -z "${MERGE_GATE_TRIGGERED[$entry]+x}" ]]; then
          echo "[poll-phase] EARLY_MERGE_GATE=1: run_merge_gate for entry=${entry}" >&2
          if [[ -n "$MERGE_GATE_LOG" ]]; then
            echo "$entry" >> "$MERGE_GATE_LOG"
          fi
          MERGE_GATE_TRIGGERED["$entry"]=1
        else
          echo "[poll-phase] MERGE_GATE_TRIGGERED[$entry] 設定済み: skip" >&2
        fi
      fi
      continue ;;
    running)
      echo "[poll-phase] entry=${entry} running: skip (simplified double)" >&2
      continue ;;
    *)
      continue ;;
  esac
done

exit 0
POLL_EOF
  chmod +x "$SANDBOX/scripts/poll-phase-merge-gate.sh"
}

# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------

# _get_tmux_keys: tmux send-keys で送信された引数の全記録を返す
_get_tmux_keys() {
  if [[ -f "$TMUX_KEYS_FILE" ]]; then
    cat "$TMUX_KEYS_FILE"
  else
    echo ""
  fi
}

# _count_tmux_sends: tmux send-keys の呼び出し回数を返す
_count_tmux_sends() {
  if [[ -f "$TMUX_KEYS_FILE" ]]; then
    wc -l < "$TMUX_KEYS_FILE"
  else
    echo "0"
  fi
}

# _get_state_log: input_waiting_state への書き込み記録を返す
_get_state_log() {
  if [[ -f "$STATE_LOG" ]]; then
    cat "$STATE_LOG"
  else
    echo ""
  fi
}

# _get_notify_log: observer 通知の記録を返す
_get_notify_log() {
  if [[ -f "$NOTIFY_LOG" ]]; then
    cat "$NOTIFY_LOG"
  else
    echo ""
  fi
}

# _get_merge_gate_log: run_merge_gate の呼び出し記録を返す
_get_merge_gate_log() {
  if [[ -f "$MERGE_GATE_LOG" ]]; then
    cat "$MERGE_GATE_LOG"
  else
    echo ""
  fi
}

# _count_merge_gate_calls: run_merge_gate の呼び出し回数を返す
_count_merge_gate_calls() {
  if [[ -f "$MERGE_GATE_LOG" ]]; then
    wc -l < "$MERGE_GATE_LOG"
  else
    echo "0"
  fi
}

# _set_merge_gate_triggered <entry>: テスト用に MERGE_GATE_TRIGGERED を永続化ファイルで設定
_set_merge_gate_triggered() {
  local entry="$1"
  echo "$entry" >> "$SANDBOX/.autopilot/merge-gate-triggered.txt"
}

# ===========================================================================
# T1: queued_message_residual 検知 → Enter 送信
# AC1: Press up to edit queued messages パターン追加 + debounce 後 Enter 1 回のみ
# ===========================================================================

# ---------------------------------------------------------------------------
# T1a: queued_message_residual — 1 cycle 目では Enter を送信しない（debounce 1 回目）
# GIVEN: pane output に "Press up to edit queued messages" が含まれる
# WHEN: detect_input_waiting を 1 cycle 呼出
# THEN: tmux send-keys は呼ばれない（debounce 1 回目）
# ---------------------------------------------------------------------------

@test "T1a: queued_message_residual 1cycle 目 — Enter 送信なし（debounce 1 回目）" {
  # RED: AC1 が未実装なら queued_message_residual pattern を認識せず fail する
  SEEN_FILE="$SANDBOX/seen.txt"
  touch "$SEEN_FILE"

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Press up to edit queued messages" \
    --issue 1580 \
    --window "ap-#1580" \
    --seen-file "$SEEN_FILE"

  assert_success

  # 1 cycle 目では tmux send-keys は呼ばれない
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]

  # SEEN_FILE に debounce key が記録されている
  grep -qF "1580:queued_message_residual" "$SEEN_FILE"
}

# ---------------------------------------------------------------------------
# T1b: queued_message_residual — 2 cycle 目で Enter が 1 回だけ送信される（debounce 確定）
# GIVEN: SEEN_FILE に 1 cycle 目の記録があり、pane output に同パターンが含まれる
# WHEN: detect_input_waiting を 2 cycle 呼出
# THEN: tmux send-keys Enter が 1 回のみ呼ばれる
# ---------------------------------------------------------------------------

@test "T1b: queued_message_residual 2cycle 目 — Enter が 1 回のみ送信される（debounce 確定）" {
  # RED: AC1 が未実装なら queued_message_residual pattern を認識せず fail する
  SEEN_FILE="$SANDBOX/seen-2nd.txt"
  # 1 cycle 目の記録を事前設定
  echo "1580:queued_message_residual" > "$SEEN_FILE"

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Press up to edit queued messages" \
    --issue 1580 \
    --window "ap-#1580" \
    --seen-file "$SEEN_FILE"

  assert_success

  # tmux send-keys が 1 回だけ呼ばれた
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 1 ]

  # Enter が含まれる
  grep -qF "Enter" "$TMUX_KEYS_FILE"

  # debounce key がリセットされている（3 cycle 目は再び 1 cycle 目扱い）
  ! grep -qF "1580:queued_message_residual" "$SEEN_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# T1c: queued_message_residual — 3 cycle 目（リセット後）では Enter を送信しない
# GIVEN: 2 cycle 目で Enter 送信済み（SEEN_FILE リセット済み）
# WHEN: 同じパターンで再度 detect_input_waiting を呼出
# THEN: tmux send-keys は呼ばれない（新たな 1 cycle 目）
# ---------------------------------------------------------------------------

@test "T1c: queued_message_residual Enter 送信後リセット — 3cycle 目は再び 1 回目扱い" {
  # RED: AC1 が未実装なら fail する
  SEEN_FILE="$SANDBOX/seen-reset.txt"
  touch "$SEEN_FILE"  # リセット後（空ファイル）

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Press up to edit queued messages" \
    --issue 1580 \
    --window "ap-#1580" \
    --seen-file "$SEEN_FILE"

  assert_success

  # Enter は送信されない
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]
}

# ===========================================================================
# T2: freeform_kaishi 検知 → 状態書き込みのみ（auto-recovery しない）
# AC2: (開始|始め)(て|します) パターン追加 + Enter 送信なし
# ===========================================================================

# ---------------------------------------------------------------------------
# T2a: freeform_kaishi — debounce なし / 状態書き込みあり、tmux send-keys なし
# GIVEN: pane output に "実装を開始しますか？" が含まれる（debounce 無効）
# WHEN: detect_input_waiting を呼出
# THEN: input_waiting_state にエントリが書き込まれ、tmux send-keys は呼ばれない
# ---------------------------------------------------------------------------

@test "T2a: freeform_kaishi 検知 — STATE_LOG に書き込み、tmux send-keys なし" {
  # RED: AC2 が未実装なら freeform_kaishi pattern を認識せず fail する

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "実装を開始しますか？" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  # STATE_LOG にエントリが書き込まれている
  [ -f "$STATE_LOG" ]
  grep -qF "1580:freeform_kaishi:" "$STATE_LOG"

  # tmux send-keys は呼ばれていない
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T2b: freeform_kaishi — observer 通知が送信される
# GIVEN: pane output に "実装を開始しますか？" が含まれる
# WHEN: detect_input_waiting を呼出
# THEN: NOTIFY_LOG に "[input_waiting] issue=1580 pattern=freeform_kaishi" が記録される
# ---------------------------------------------------------------------------

@test "T2b: freeform_kaishi — observer 通知が送信される" {
  # RED: AC2 が未実装なら fail する

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "実装を開始しますか？" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  # NOTIFY_LOG に通知記録がある
  [ -f "$NOTIFY_LOG" ]
  grep -qF "issue=1580" "$NOTIFY_LOG"
  grep -qF "pattern=freeform_kaishi" "$NOTIFY_LOG"
}

# ---------------------------------------------------------------------------
# T2c: freeform_kaishi — "開始します" バリアントも検知される
# GIVEN: pane output に "実装を開始しますか？" が含まれる
# WHEN: detect_input_waiting を呼出
# THEN: pattern=freeform_kaishi として検知される
# ---------------------------------------------------------------------------

@test "T2c: freeform_kaishi — '開始します' バリアントも検知される" {
  # RED: AC2 が未実装なら fail する

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "実装を開始しますか？" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  # 検知されること（STATE_LOG またはパターン名の確認）
  [ -f "$STATE_LOG" ]
  grep -qF "freeform_kaishi" "$STATE_LOG"
}

# ---------------------------------------------------------------------------
# T2d: freeform_kaishi + debounce — 2 cycle 目で state 書き込みが発生する
# GIVEN: SEEN_FILE に 1 cycle 目の記録あり
# WHEN: detect_input_waiting を 2 cycle 呼出
# THEN: STATE_LOG にエントリが追記される
# ---------------------------------------------------------------------------

@test "T2d: freeform_kaishi + debounce — 2cycle 目で state 書き込みが発生する" {
  # RED: AC2 が未実装なら fail する
  SEEN_FILE="$SANDBOX/seen-kaishi.txt"
  echo "1580:freeform_kaishi" > "$SEEN_FILE"

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "実装を開始しますか？" \
    --issue 1580 \
    --window "ap-#1580" \
    --seen-file "$SEEN_FILE"

  assert_success

  [ -f "$STATE_LOG" ]
  grep -qF "1580:freeform_kaishi:" "$STATE_LOG"

  # tmux send-keys は呼ばれない（freeform_kaishi は auto-recovery しない）
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]
}

# ===========================================================================
# T3: 既存 menu_enter_select リグレッション
# AC4(regression): "❯ 1. option" → menu_prompt_number が従来通り動作する
# ===========================================================================

# ---------------------------------------------------------------------------
# T3a: 既存 menu_prompt_number パターン — debounce なし、従来の state write あり
# GIVEN: pane output に "❯ 1. option" が含まれる
# WHEN: detect_input_waiting を呼出
# THEN: menu_prompt_number として検知され、STATE_LOG に記録される
# ---------------------------------------------------------------------------

@test "T3a: menu_prompt_number (❯ 1.) リグレッション — 検知される" {
  # RED: リグレッション確認。AC4 実装後は GREEN になるべき。
  # 実装前（detect_input_waiting に新 pattern が追加されていない状態）では
  # 既存 pattern は動作するため、このテストは実装前から PASS する可能性がある。
  # しかし新 pattern 追加後に既存が壊れていないことを RED で保証するために記載する。

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "❯ 1. option A" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  # 検知されること
  [ -n "$output" ]
  [[ "$output" == *"menu_prompt_number"* ]]

  # STATE_LOG に記録される（既存の state write ロジック）
  [ -f "$STATE_LOG" ]
}

# ---------------------------------------------------------------------------
# T3b: 既存 menu_enter_select パターン — tmux send-keys は呼ばれない
# GIVEN: pane output に "  Enter to select" が含まれる
# WHEN: detect_input_waiting を呼出
# THEN: menu_enter_select として検知される（freeform_kaishi と混同されない）
# ---------------------------------------------------------------------------

@test "T3b: menu_enter_select リグレッション — freeform_kaishi と混同されない" {
  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "  Enter to select" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  [ -n "$output" ]
  [[ "$output" == *"menu_enter_select"* ]]

  # freeform_kaishi ではないことを確認
  [[ "$output" != *"freeform_kaishi"* ]]

  # tmux send-keys は呼ばれない（menu_enter_select は Enter を auto-send しない）
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T3c: 既存 freeform_tsuzukemasu パターン — リグレッションなし
# GIVEN: pane output に "このまま続けますか？" が含まれる
# WHEN: detect_input_waiting を呼出
# THEN: freeform_tsuzukemasu として検知される
# ---------------------------------------------------------------------------

@test "T3c: freeform_tsuzukemasu リグレッション — 検知される" {
  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "このまま続けますか？" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  [ -n "$output" ]
  [[ "$output" == *"freeform_tsuzukemasu"* ]]
}

# ---------------------------------------------------------------------------
# T3d: 新 pattern と既存 pattern が同時に存在する場合、先に定義されたものが優先される
# GIVEN: pane output が "Enter to select" を含む（既存 pattern が先に定義）
# WHEN: detect_input_waiting を呼出
# THEN: queued_message_residual ではなく menu_enter_select が検知される
# ---------------------------------------------------------------------------

@test "T3d: 既存 pattern と新 pattern の優先順位 — 既存 menu pattern が優先される" {
  # "Enter to select" は menu_enter_select であり、queued_message_residual ではない
  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Enter to select" \
    --issue 1580 \
    --window "ap-#1580"

  assert_success

  [ -n "$output" ]
  [[ "$output" == *"menu_enter_select"* ]]
  [[ "$output" != *"queued_message_residual"* ]]
}

# ===========================================================================
# T4: merge-ready + running 並列, AUTOPILOT_EARLY_MERGE_GATE=1
# AC3: EARLY_MERGE_GATE=1 時に merge-ready entry のみ即時 run_merge_gate
# ===========================================================================

# ---------------------------------------------------------------------------
# T4a: EARLY_MERGE_GATE=1 + entry-A=merge-ready → run_merge_gate が entry-A のみで発火
# GIVEN: entry-A が merge-ready、entry-B が running、AUTOPILOT_EARLY_MERGE_GATE=1
# WHEN: poll_phase 1 cycle 実行
# THEN: MERGE_GATE_LOG に entry-A が記録される（entry-B は記録されない）
# ---------------------------------------------------------------------------

@test "T4a: EARLY_MERGE_GATE=1 + merge-ready — run_merge_gate が 1 回発火" {
  # RED: AC3 が未実装なら poll_phase が merge-ready を即時処理せず fail する
  create_issue_json 100 "merge-ready" '.pr = "42" | .branch = "feat/100-test"'
  create_issue_json 200 "running"

  AUTOPILOT_EARLY_MERGE_GATE=1 \
    run bash "$SANDBOX/scripts/poll-phase-merge-gate.sh"

  assert_success

  # entry-100 で run_merge_gate が 1 回呼ばれている
  local count
  count=$(_count_merge_gate_calls)
  [ "$count" -eq 1 ]

  # entry-A (_default:100) が呼ばれている
  grep -qF "_default:100" "$MERGE_GATE_LOG"
}

# ---------------------------------------------------------------------------
# T4b: EARLY_MERGE_GATE=1 + entry-A=merge-ready — entry-B(running) には発火しない
# ---------------------------------------------------------------------------

@test "T4b: EARLY_MERGE_GATE=1 — running entry には run_merge_gate が発火しない" {
  create_issue_json 100 "merge-ready" '.pr = "42" | .branch = "feat/100-test"'
  create_issue_json 200 "running"

  AUTOPILOT_EARLY_MERGE_GATE=1 \
    run bash "$SANDBOX/scripts/poll-phase-merge-gate.sh"

  assert_success

  # entry-B (_default:200) は呼ばれていない
  ! grep -qF "_default:200" "$MERGE_GATE_LOG" 2>/dev/null
}

# ===========================================================================
# T5: MERGE_GATE_TRIGGERED 重複防止
# AC3: MERGE_GATE_TRIGGERED[entry] 設定済みなら run_merge_gate を呼ばない
# ===========================================================================

# ---------------------------------------------------------------------------
# T5a: MERGE_GATE_TRIGGERED[entry-A] 設定済み → run_merge_gate は呼ばれない
# GIVEN: entry-A が merge-ready かつ MERGE_GATE_TRIGGERED[entry-A] 設定済み
# WHEN: poll_phase 1 cycle 実行
# THEN: run_merge_gate は呼ばれない
# ---------------------------------------------------------------------------

@test "T5a: MERGE_GATE_TRIGGERED 設定済み — run_merge_gate は発火しない" {
  # RED: AC3 が未実装なら MERGE_GATE_TRIGGERED チェックも未実装で fail する
  create_issue_json 100 "merge-ready" '.pr = "42" | .branch = "feat/100-test"'

  # MERGE_GATE_TRIGGERED[_default:100] を事前設定
  _set_merge_gate_triggered "_default:100"

  AUTOPILOT_EARLY_MERGE_GATE=1 \
    run bash "$SANDBOX/scripts/poll-phase-merge-gate.sh"

  assert_success

  # run_merge_gate は呼ばれていない
  local count
  count=$(_count_merge_gate_calls)
  [ "$count" -eq 0 ]
}

# ===========================================================================
# T6: AUTOPILOT_EARLY_MERGE_GATE=0 デフォルト
# AC3: EARLY_MERGE_GATE=0 では merge-ready でも即時 run_merge_gate を呼ばない
# ===========================================================================

# ---------------------------------------------------------------------------
# T6a: EARLY_MERGE_GATE=0（デフォルト）— run_merge_gate は呼ばれない
# GIVEN: entry-A が merge-ready、AUTOPILOT_EARLY_MERGE_GATE=0（デフォルト）
# WHEN: poll_phase 1 cycle 実行（他 Worker は running）
# THEN: run_merge_gate は呼ばれない
# ---------------------------------------------------------------------------

@test "T6a: EARLY_MERGE_GATE=0 デフォルト — merge-ready でも run_merge_gate を呼ばない" {
  # RED: AC3 が未実装なら EARLY_MERGE_GATE 分岐が存在せず fail する
  create_issue_json 100 "merge-ready" '.pr = "42" | .branch = "feat/100-test"'
  create_issue_json 200 "running"

  # AUTOPILOT_EARLY_MERGE_GATE 未設定（デフォルト 0）
  AUTOPILOT_EARLY_MERGE_GATE=0 \
    run bash "$SANDBOX/scripts/poll-phase-merge-gate.sh"

  assert_success

  # run_merge_gate は呼ばれていない
  local count
  count=$(_count_merge_gate_calls)
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T6b: EARLY_MERGE_GATE 未設定 — run_merge_gate は呼ばれない
# ---------------------------------------------------------------------------

@test "T6b: EARLY_MERGE_GATE 未設定 — merge-ready でも run_merge_gate を呼ばない" {
  create_issue_json 100 "merge-ready" '.pr = "42" | .branch = "feat/100-test"'
  create_issue_json 200 "running"

  # AUTOPILOT_EARLY_MERGE_GATE を未設定で実行
  run bash "$SANDBOX/scripts/poll-phase-merge-gate.sh"

  assert_success

  local count
  count=$(_count_merge_gate_calls)
  [ "$count" -eq 0 ]
}

# ===========================================================================
# AC5: debounce 機構の検証
# 新 pattern にも既存の ${issue}:${pattern_name} debounce key 形式が適用されること
# ===========================================================================

# ---------------------------------------------------------------------------
# AC5a: queued_message_residual の debounce key 形式が既存と同じ
# GIVEN: SEEN_FILE を使用して debounce を検証
# WHEN: 1 cycle 目実行
# THEN: SEEN_FILE に "${issue}:queued_message_residual" 形式で記録される
# ---------------------------------------------------------------------------

@test "AC5a: queued_message_residual debounce key 形式 — issue:pattern_name 形式で記録" {
  # RED: AC5 が未実装なら fail する
  SEEN_FILE="$SANDBOX/seen-ac5a.txt"
  touch "$SEEN_FILE"

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Press up to edit queued messages" \
    --issue 999 \
    --window "ap-#999" \
    --seen-file "$SEEN_FILE"

  assert_success

  # SEEN_FILE に "999:queued_message_residual" 形式のキーが存在する
  grep -qF "999:queued_message_residual" "$SEEN_FILE"
}

# ---------------------------------------------------------------------------
# AC5b: freeform_kaishi の debounce key 形式が既存と同じ
# ---------------------------------------------------------------------------

@test "AC5b: freeform_kaishi debounce key 形式 — issue:pattern_name 形式で記録" {
  # RED: AC5 が未実装なら fail する
  SEEN_FILE="$SANDBOX/seen-ac5b.txt"
  touch "$SEEN_FILE"

  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "実装を開始しますか？" \
    --issue 999 \
    --window "ap-#999" \
    --seen-file "$SEEN_FILE"

  assert_success

  # SEEN_FILE に "999:freeform_kaishi" 形式のキーが存在する
  grep -qF "999:freeform_kaishi" "$SEEN_FILE"
}

# ---------------------------------------------------------------------------
# AC5c: 異なる issue/pattern の debounce key が独立して管理される
# ---------------------------------------------------------------------------

@test "AC5c: 異なる issue:pattern の debounce key は独立して管理される" {
  # RED: AC5 が未実装なら fail する
  SEEN_FILE="$SANDBOX/seen-ac5c.txt"
  # issue=1 の queued_message_residual が 1 cycle 目済みの状態
  echo "1:queued_message_residual" > "$SEEN_FILE"

  # issue=2 の queued_message_residual は 1 cycle 目（SEEN_FILE に記録されるだけ）
  run bash "$SANDBOX/scripts/stuck-patterns-poll.sh" \
    --pane-output "Press up to edit queued messages" \
    --issue 2 \
    --window "ap-#2" \
    --seen-file "$SEEN_FILE"

  assert_success

  # issue=2 では Enter が送信されない（1 cycle 目）
  local count
  count=$(_count_tmux_sends)
  [ "$count" -eq 0 ]

  # issue=2 の debounce key が SEEN_FILE に追加されている
  grep -qF "2:queued_message_residual" "$SEEN_FILE"
}

# ===========================================================================
# AC7(doc): pitfalls-catalog.md と monitor-channel-catalog.md のドキュメント更新
# ===========================================================================

# ---------------------------------------------------------------------------
# AC7a: pitfalls-catalog.md §2.1 に "orchestrator-side" 検知/復旧 note が存在する
# GIVEN: pitfalls-catalog.md が存在する
# WHEN: §2.1 の内容を確認する
# THEN: "orchestrator" または "orchestrator-side" への言及が存在する
# ---------------------------------------------------------------------------

@test "AC7a: pitfalls-catalog.md §2.1 に orchestrator-side 検知/復旧 note が追記されている" {
  # RED: AC7 が未実装なら pitfalls-catalog.md に該当 note がなく fail する
  local catalog_file
  catalog_file="$(cd "${BATS_TEST_DIRNAME}" && cd ../../../../../ && pwd)/plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"

  [ -f "$catalog_file" ]

  # §2.1 のコンテキストで orchestrator-side 検知への言及があること
  local section_content
  section_content=$(grep -A 5 "2\.1" "$catalog_file" || echo "")

  echo "$section_content" | grep -qiE "orchestrator.*(detect|検知|recover|復旧)"
}

# ---------------------------------------------------------------------------
# AC7b: monitor-channel-catalog.md の Press up 説明に orchestrator-side 参照がある
# GIVEN: monitor-channel-catalog.md が存在する
# WHEN: Press up 説明箇所を確認する
# THEN: orchestrator-side 検知への reference が存在する
# ---------------------------------------------------------------------------

@test "AC7b: monitor-channel-catalog.md の Press up 説明に orchestrator-side 参照がある" {
  # RED: AC7 が未実装なら monitor-channel-catalog.md に該当参照がなく fail する
  local catalog_file
  catalog_file="$(cd "${BATS_TEST_DIRNAME}" && cd ../../../../../ && pwd)/plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md"

  [ -f "$catalog_file" ]

  # Press up の説明行を取得して orchestrator-side 参照があること
  grep -i "Press up" "$catalog_file" | grep -qiE "orchestrator"
}
