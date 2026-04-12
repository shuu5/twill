#!/usr/bin/env bats
# autopilot-orchestrator.bats
# Requirement: health-check-orchestrator-integration
#
# health-check 統合ロジックは autopilot-orchestrator.sh に埋め込まれているため、
# 対象ロジックのみを抽出した test double スクリプト (health-check-poll.sh) で動作を検証する。
#
# Spec: openspec/changes/health-check-orchestrator-integration/specs/health-check-integration/spec.md

load '../helpers/common'

# ---------------------------------------------------------------------------
# setup: test double スクリプトを生成
# ---------------------------------------------------------------------------
# health-check-poll.sh: poll_single() 内の health-check 呼び出しロジックのみを抽出
#
# 引数:
#   --issue N              Issue 番号
#   --window NAME          tmux window 名
#   --poll-count N         現在のポーリングカウンタ値
#   --health-check-interval N   HEALTH_CHECK_INTERVAL（デフォルト 6）
#   --crash-exit N         crash-detect.sh の終了コード（デフォルト 0）
#   --check-and-nudge-matched   このフラグがあれば check_and_nudge はパターンマッチ成功扱い
#
# 環境変数:
#   AUTOPILOT_DIR          .autopilot ディレクトリパス
#   MAX_NUDGE              nudge 上限（デフォルト 3）
#
# 終了コード: 常に 0（内部ロジックの検証は stdout/ファイルで行う）
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # HEALTH_CHECK_INTERVAL デフォルト値
  export HEALTH_CHECK_INTERVAL=6
  export MAX_NUDGE="${DEV_AUTOPILOT_MAX_NUDGE:-3}"

  # デフォルト: tmux send-keys は記録するだけ
  SENT_KEYS_FILE="$SANDBOX/tmux-sent-keys.txt"
  export SENT_KEYS_FILE

  # デフォルト: state-write.sh の呼び出しを記録
  STATE_WRITE_LOG="$SANDBOX/state-write-calls.txt"
  export STATE_WRITE_LOG

  # tmux stub: capture-pane と send-keys を処理
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  capture-pane)
    # health-check.sh が内部で呼ぶ capture-pane — 空を返す
    exit 0 ;;
  send-keys)
    # 送信されたキーを記録: "tmux send-keys -t <window> <text> Enter"
    shift  # remove "send-keys"
    shift  # remove "-t"
    shift  # remove window name
    # 残りが送信テキスト (最後の "Enter" を除く)
    args=("\$@")
    # "Enter" が最後の引数として来る; その前を記録
    count=\${#args[@]}
    if [[ \$count -ge 2 ]]; then
      text="\${args[*]:0:\$((count-1))}"
    else
      text=""
    fi
    printf '%s\n' "\$text" >> "$SENT_KEYS_FILE"
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # state-write.sh stub: 呼び出し引数をファイルに記録し、実際のファイルにも反映
  cat > "$SANDBOX/scripts/state-write.sh" <<'REAL_STATE_WRITE_EOF'
#!/usr/bin/env bash
# stub: 引数を記録してから実際の状態書き込みをシミュレート
set -euo pipefail

AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
issue=""
status_val=""
failure_msg=""

# 引数パース
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --issue) issue="${args[$((i+1))]}"; i=$((i+1)) ;;
    --set)
      val="${args[$((i+1))]}"; i=$((i+1))
      if [[ "$val" == status=* ]]; then
        status_val="${val#status=}"
      fi
      ;;
  esac
done

# 呼び出し内容をログに記録
echo "$*" >> "${STATE_WRITE_LOG:-/dev/null}"

# 実際の issue JSON を更新（issue 番号と status が判明している場合）
if [[ -n "$AUTOPILOT_DIR" && -n "$issue" && -n "$status_val" ]]; then
  issue_file="$AUTOPILOT_DIR/issues/issue-${issue}.json"
  if [[ -f "$issue_file" ]]; then
    tmp=$(mktemp)
    jq --arg s "$status_val" '.status = $s' "$issue_file" > "$tmp" && mv "$tmp" "$issue_file"
  fi
fi
REAL_STATE_WRITE_EOF
  chmod +x "$SANDBOX/scripts/state-write.sh"

  # テスト用 health-check-poll.sh test double を生成
  # このスクリプトは poll_single() の running ブランチ内 health-check 連携ロジックを再現する
  cat > "$SANDBOX/scripts/health-check-poll.sh" <<'POLL_EOF'
#!/usr/bin/env bash
# health-check-poll.sh — poll_single() の health-check 統合ロジック test double
# orchestrator の health-check 呼び出し・nudge・failed 遷移のみを抽出して検証する
set -euo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-6}"
MAX_NUDGE="${MAX_NUDGE:-3}"

# --- 引数パース ---
ISSUE=""
WINDOW_NAME=""
POLL_COUNT=""
CRASH_EXIT=0
CHECK_AND_NUDGE_MATCHED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)                  ISSUE="$2"; shift 2 ;;
    --window)                 WINDOW_NAME="$2"; shift 2 ;;
    --poll-count)             POLL_COUNT="$2"; shift 2 ;;
    --health-check-interval)  HEALTH_CHECK_INTERVAL="$2"; shift 2 ;;
    --crash-exit)             CRASH_EXIT="$2"; shift 2 ;;
    --check-and-nudge-matched) CHECK_AND_NUDGE_MATCHED=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ISSUE" || -z "$WINDOW_NAME" || -z "$POLL_COUNT" ]]; then
  echo "Error: --issue, --window, --poll-count are required" >&2
  exit 1
fi

# 連想配列（テスト用にシングルトン管理）
declare -A NUDGE_COUNTS=()
# 既存の NUDGE_COUNTS を state ファイルから読む（テスト間状態管理）
nudge_state_file="${AUTOPILOT_DIR}/issues/issue-${ISSUE}-nudge-count.txt"
if [[ -f "$nudge_state_file" ]]; then
  NUDGE_COUNTS[$ISSUE]="$(cat "$nudge_state_file")"
fi

# -----------------------------------------------------------------------
# poll_single() running ブランチの health-check 統合ロジック（仕様準拠）
# -----------------------------------------------------------------------

# Step 1: crash-detect 後は health-check をスキップ (Scenario 2)
if [[ "$CRASH_EXIT" -eq 2 ]]; then
  echo "[poll] crash-detect exit 2 — skipping health-check" >&2
  exit 0
fi

# Step 2: HEALTH_CHECK_INTERVAL の倍数チェック (Scenario 1)
if (( POLL_COUNT % HEALTH_CHECK_INTERVAL != 0 )); then
  # 非倍数サイクル — health-check 呼び出しなし
  echo "[poll] poll_count=${POLL_COUNT} not a multiple of HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL} — skip" >&2
  exit 0
fi

echo "[poll] poll_count=${POLL_COUNT} is multiple of ${HEALTH_CHECK_INTERVAL} — calling health-check.sh" >&2

# Step 3: health-check.sh を実行
hc_exit=0
hc_stderr=""
hc_stderr=$(bash "$SCRIPTS_ROOT/health-check.sh" \
  --issue "$ISSUE" \
  --window "$WINDOW_NAME" 2>&1 >/dev/null) || hc_exit=$?

echo "[poll] health-check.sh exit=${hc_exit} stderr='${hc_stderr}'" >&2

# Step 4: health-check exit 0 — 正常
if [[ "$hc_exit" -eq 0 ]]; then
  exit 0
fi

# Step 5: health-check exit 1 + stderr あり → 引数エラー扱い、スキップ (Scenario 4)
if [[ -n "$hc_stderr" ]]; then
  echo "[poll] health-check stderr non-empty — skipping nudge (arg error)" >&2
  exit 0
fi

# Step 6: check_and_nudge がパターンマッチ成功なら追加 nudge しない (Scenario 5)
if [[ "$CHECK_AND_NUDGE_MATCHED" == "true" ]]; then
  echo "[poll] check_and_nudge matched — no additional health-check nudge" >&2
  exit 0
fi

# Step 7: health-check exit 1 + stderr なし → stall 検知 (Scenarios 3, 6)
current_count="${NUDGE_COUNTS[$ISSUE]:-0}"

if [[ "$current_count" -ge "$MAX_NUDGE" ]]; then
  # Scenario 6: nudge 上限到達 → failed 遷移
  echo "[poll] NUDGE_COUNTS[${ISSUE}]=${current_count} >= MAX_NUDGE=${MAX_NUDGE} — transitioning to failed" >&2
  python3 -m twl.autopilot.state write \
    --type issue --issue "$ISSUE" --role pilot \
    --set "status=failed" \
    --set 'failure={"message":"health_check_stall","step":"polling"}'
  exit 0
fi

# Scenario 3: nudge 上限未満 → Enter nudge 送信 + NUDGE_COUNTS インクリメント
echo "[poll] stall detected — sending nudge (${current_count}/${MAX_NUDGE})" >&2
tmux send-keys -t "$WINDOW_NAME" "" Enter 2>/dev/null || true
new_count=$((current_count + 1))
NUDGE_COUNTS[$ISSUE]="$new_count"

# nudge count を永続化（次のテスト呼び出しで参照可能にする）
echo "$new_count" > "$nudge_state_file"

exit 0
POLL_EOF
  chmod +x "$SANDBOX/scripts/health-check-poll.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# ヘルパー: health-check.sh のスタブ生成（exit code + stderr を制御）
# ---------------------------------------------------------------------------

# _stub_health_check <exit_code> [stderr_text]
# exit_code: 0=正常, 1=stall/error検知
# stderr_text: 空ならスタブは stderr を出力しない（= 正常なstall検知）
#              非空ならスタブは stderr に出力（= 引数エラー扱い）
_stub_health_check() {
  local exit_code="$1"
  local stderr_text="${2:-}"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
${stderr_text:+printf '%s\n' "$stderr_text" >&2}
exit $exit_code
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"
}

# _get_sent_keys: tmux send-keys で送信されたテキストを返す
_get_sent_keys() {
  if [[ -f "$SENT_KEYS_FILE" ]]; then
    cat "$SENT_KEYS_FILE"
  else
    echo ""
  fi
}

# _get_state_write_calls: state-write.sh が呼ばれた引数を返す
_get_state_write_calls() {
  if [[ -f "$STATE_WRITE_LOG" ]]; then
    cat "$STATE_WRITE_LOG"
  else
    echo ""
  fi
}

# _set_nudge_count <issue> <count>: テスト用に NUDGE_COUNTS を永続化ファイルで設定
_set_nudge_count() {
  local issue="$1"
  local count="$2"
  echo "$count" > "$SANDBOX/.autopilot/issues/issue-${issue}-nudge-count.txt"
}

# ===========================================================================
# Requirement: health-check 定期呼び出し
# Spec: specs/health-check-integration/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: health-check が定期実行される
# WHEN poll カウンタが HEALTH_CHECK_INTERVAL の倍数に達した
# THEN health-check.sh --issue <issue> --window <window> が実行される
# ---------------------------------------------------------------------------

@test "health-check-integration: poll_count が HEALTH_CHECK_INTERVAL の倍数で health-check.sh が呼ばれる" {
  create_issue_json 1 "running"
  # health-check.sh を exit 0 でスタブ化し、呼ばれたことを記録する
  cat > "$SANDBOX/scripts/health-check.sh" <<'STUB'
#!/usr/bin/env bash
# 呼び出し記録
printf '%s\n' "$*" >> "${SANDBOX_HEALTH_CHECK_LOG:-/dev/null}"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  HEALTH_CHECK_LOG="$SANDBOX/health-check-calls.txt"
  export HEALTH_CHECK_LOG

  # health-check.sh 内で SANDBOX_HEALTH_CHECK_LOG を参照できるようにする
  SANDBOX_HEALTH_CHECK_LOG="$HEALTH_CHECK_LOG" \
    run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6 \
    --health-check-interval 6

  assert_success

  # health-check.sh が呼ばれたことを確認
  [ -f "$HEALTH_CHECK_LOG" ]
}

@test "health-check-integration: poll_count=12 (2×HEALTH_CHECK_INTERVAL) でも health-check.sh が呼ばれる" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 12 \
    --health-check-interval 6

  assert_success
  [ -f "$HEALTH_CHECK_CALLED" ]
}

@test "health-check-integration: poll_count が HEALTH_CHECK_INTERVAL の非倍数では health-check.sh を呼ばない" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  # poll_count=5 は HEALTH_CHECK_INTERVAL=6 の倍数ではない
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 5 \
    --health-check-interval 6

  assert_success
  # health-check.sh は呼ばれていない
  [ ! -f "$HEALTH_CHECK_CALLED" ]
}

@test "health-check-integration: poll_count=1 (非倍数) では health-check.sh を呼ばない" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 1 \
    --health-check-interval 6

  assert_success
  [ ! -f "$HEALTH_CHECK_CALLED" ]
}

# ---------------------------------------------------------------------------
# Scenario: crash-detect 後は health-check をスキップする
# WHEN crash-detect.sh が exit 2 を返した
# THEN 同じポーリングサイクルで health-check を実行してはならない
# ---------------------------------------------------------------------------

@test "health-check-integration: crash-detect exit 2 のサイクルでは health-check.sh を呼ばない" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  # crash-detect exit 2 かつ poll_count は HEALTH_CHECK_INTERVAL の倍数
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6 \
    --health-check-interval 6 \
    --crash-exit 2

  assert_success
  # health-check.sh は呼ばれていない（crash-detect 後スキップ）
  [ ! -f "$HEALTH_CHECK_CALLED" ]
}

@test "health-check-integration: crash-detect exit 0 のサイクルでは health-check.sh が呼ばれる" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  # crash-detect exit 0 (= crash なし) かつ poll_count は倍数
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6 \
    --health-check-interval 6 \
    --crash-exit 0

  assert_success
  [ -f "$HEALTH_CHECK_CALLED" ]
}

# ===========================================================================
# Requirement: health-check 検知時の汎用 nudge
# Spec: specs/health-check-integration/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: stall 検知時に nudge が送信される
# WHEN health-check が exit 1 を返し、かつ stderr が空であり、かつ
#      NUDGE_COUNTS < MAX_NUDGE
# THEN tmux send-keys で空の Enter nudge が送信され、NUDGE_COUNTS がインクリメントされる
# ---------------------------------------------------------------------------

@test "health-check-integration: stall 検知時に tmux send-keys で nudge が送信される" {
  create_issue_json 1 "running"
  # health-check: exit 1、stderr 空 → stall 検知
  _stub_health_check 1 ""

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # tmux send-keys が呼ばれたことを確認
  [ -f "$SENT_KEYS_FILE" ]
  # 送信回数: 1回
  local line_count
  line_count=$(wc -l < "$SENT_KEYS_FILE")
  [ "$line_count" -ge 1 ]
}

@test "health-check-integration: stall 検知時に NUDGE_COUNTS がインクリメントされる" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # 初回 nudge (count 0 → 1)
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # nudge count が 1 になっていること
  local nudge_file="$SANDBOX/.autopilot/issues/issue-1-nudge-count.txt"
  [ -f "$nudge_file" ]
  local count
  count=$(cat "$nudge_file")
  [ "$count" -eq 1 ]
}

@test "health-check-integration: nudge カウントが累積される（2回目は count=2）" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # count を 1 に設定してから実行
  _set_nudge_count 1 1

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  local count
  count=$(cat "$SANDBOX/.autopilot/issues/issue-1-nudge-count.txt")
  [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Scenario: health-check 引数エラーはスキップされる
# WHEN health-check が exit 1 を返し、かつ stderr に出力がある
# THEN nudge を送信せず処理をスキップする
# ---------------------------------------------------------------------------

@test "health-check-integration: health-check exit 1 + stderr あり → nudge 送信しない（引数エラーはスキップ）" {
  create_issue_json 1 "running"
  # health-check: exit 1 + stderr に出力あり
  _stub_health_check 1 "Error: --issue is required"

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # tmux send-keys は呼ばれていない
  [ ! -f "$SENT_KEYS_FILE" ]
}

@test "health-check-integration: health-check exit 1 + stderr あり → state-write.sh を呼ばない" {
  create_issue_json 1 "running"
  _stub_health_check 1 "--window is required"

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # state-write.sh は呼ばれていない
  [ ! -f "$STATE_WRITE_LOG" ]
}

@test "health-check-integration: health-check exit 1 + stderr 空 → nudge 送信される（正常な stall 検知）" {
  create_issue_json 1 "running"
  # exit 1 + stderr 空 = stall 検知
  _stub_health_check 1 ""

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success
  [ -f "$SENT_KEYS_FILE" ]
}

# ---------------------------------------------------------------------------
# Scenario: check_and_nudge が優先される
# WHEN check_and_nudge がパターンマッチに成功した
# THEN health-check による追加の nudge を送信してはならない
# ---------------------------------------------------------------------------

@test "health-check-integration: check_and_nudge マッチ成功時は health-check nudge を送信しない" {
  create_issue_json 1 "running"
  # health-check: exit 1 + stderr 空 (stall 検知相当)
  _stub_health_check 1 ""

  # check_and_nudge がマッチした状態でポーリング
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6 \
    --check-and-nudge-matched

  assert_success

  # health-check による追加 nudge は送信されていない
  [ ! -f "$SENT_KEYS_FILE" ]
}

@test "health-check-integration: check_and_nudge マッチ成功時は NUDGE_COUNTS をインクリメントしない" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6 \
    --check-and-nudge-matched

  assert_success

  # nudge count ファイルは作成されていない（0 のまま）
  local nudge_file="$SANDBOX/.autopilot/issues/issue-1-nudge-count.txt"
  [ ! -f "$nudge_file" ]
}

@test "health-check-integration: check_and_nudge 非マッチ時は health-check nudge が送信される（対比ケース）" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # --check-and-nudge-matched フラグなし
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success
  [ -f "$SENT_KEYS_FILE" ]
}

# ===========================================================================
# Requirement: nudge 上限到達時の failed 遷移
# Spec: specs/health-check-integration/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: nudge 上限到達で failed に遷移する
# WHEN health-check が異常を検知し、かつ NUDGE_COUNTS >= MAX_NUDGE
# THEN state-write.sh で status=failed、failure.message=health_check_stall が書き込まれる
# ---------------------------------------------------------------------------

@test "health-check-integration: NUDGE_COUNTS >= MAX_NUDGE で status=failed に遷移する" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # NUDGE_COUNTS を MAX_NUDGE (=3) に設定
  _set_nudge_count 1 3

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # state-write.sh が status=failed で呼ばれたことを確認
  [ -f "$STATE_WRITE_LOG" ]
  grep -q "status=failed" "$STATE_WRITE_LOG"
}

@test "health-check-integration: NUDGE_COUNTS >= MAX_NUDGE で failure.message=health_check_stall が書き込まれる" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  _set_nudge_count 1 3

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  grep -q "health_check_stall" "$STATE_WRITE_LOG"
}

@test "health-check-integration: NUDGE_COUNTS >= MAX_NUDGE で issue JSON の status が failed に更新される" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  _set_nudge_count 1 3

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # issue JSON の status を確認
  local new_status
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]
}

@test "health-check-integration: NUDGE_COUNTS = MAX_NUDGE - 1 では failed に遷移しない（境界値）" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # MAX_NUDGE=3 の場合、count=2 は上限未満 → nudge 送信
  _set_nudge_count 1 2

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # state-write.sh で status=failed は呼ばれていない
  if [ -f "$STATE_WRITE_LOG" ]; then
    # state-write は呼ばれているかもしれないが failed ではないこと
    ! grep -q "status=failed" "$STATE_WRITE_LOG"
  fi

  # 代わりに nudge が送信されている
  [ -f "$SENT_KEYS_FILE" ]
}

@test "health-check-integration: NUDGE_COUNTS >= MAX_NUDGE では追加 nudge を送信しない" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  _set_nudge_count 1 3

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # tmux send-keys（nudge）は呼ばれていない
  [ ! -f "$SENT_KEYS_FILE" ]
}

@test "health-check-integration: NUDGE_COUNTS > MAX_NUDGE でも failed に遷移する（超過ケース）" {
  create_issue_json 1 "running"
  _stub_health_check 1 ""

  # MAX_NUDGE=3 を超えた count=5 でも同様に failed 遷移
  _set_nudge_count 1 5

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  [ -f "$STATE_WRITE_LOG" ]
  grep -q "status=failed" "$STATE_WRITE_LOG"
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "health-check-integration: health-check exit 0 では nudge も failed 遷移もしない" {
  create_issue_json 1 "running"
  # health-check 正常終了
  _stub_health_check 0 ""

  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 6

  assert_success

  # nudge も state-write も呼ばれていない
  [ ! -f "$SENT_KEYS_FILE" ]
  [ ! -f "$STATE_WRITE_LOG" ]
}

@test "health-check-integration: HEALTH_CHECK_INTERVAL=1 ではすべての poll_count で health-check が呼ばれる" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  for pc in 1 2 3; do
    rm -f "$HEALTH_CHECK_CALLED"
    run bash "$SANDBOX/scripts/health-check-poll.sh" \
      --issue 1 --window "ap-#1" \
      --poll-count "$pc" \
      --health-check-interval 1

    assert_success
    [ -f "$HEALTH_CHECK_CALLED" ]
  done
}

@test "health-check-integration: --issue, --window, --poll-count 欠落時はエラー終了する" {
  run bash "$SANDBOX/scripts/health-check-poll.sh"
  assert_failure
}

@test "health-check-integration: crash-detect exit 2 かつ poll 非倍数でも health-check を呼ばない" {
  create_issue_json 1 "running"
  HEALTH_CHECK_CALLED="$SANDBOX/hc-called.flag"

  cat > "$SANDBOX/scripts/health-check.sh" <<STUB
#!/usr/bin/env bash
touch "$HEALTH_CHECK_CALLED"
exit 0
STUB
  chmod +x "$SANDBOX/scripts/health-check.sh"

  # crash あり + 非倍数 poll_count
  run bash "$SANDBOX/scripts/health-check-poll.sh" \
    --issue 1 --window "ap-#1" \
    --poll-count 5 \
    --crash-exit 2

  assert_success
  [ ! -f "$HEALTH_CHECK_CALLED" ]
}

# ===========================================================================
# Requirement: detect_input_waiting 関数が input-waiting パターンを検知しなければならない
# Spec: deltaspec/changes/issue-510/specs/input-waiting-detection/spec.md
# ===========================================================================

# ---------------------------------------------------------------------------
# セットアップ: detect-input-waiting.sh test double を SANDBOX にコピー
# ---------------------------------------------------------------------------
# 各テストは共通 setup() で生成された SANDBOX を使用し、
# detect-input-waiting.sh を "$SANDBOX/scripts/detect-input-waiting.sh" として参照する。

_setup_detect_script() {
  local scripts_src
  scripts_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cp "$scripts_src/detect-input-waiting.sh" "$SANDBOX/scripts/detect-input-waiting.sh"
  chmod +x "$SANDBOX/scripts/detect-input-waiting.sh"
}

# ===========================================================================
# Menu UI パターン検知
# Scenario: Menu UI パターンを検知する
# WHEN pane_output に Menu UI キーワードを含む行があるとき
# THEN detect_input_waiting は非空の pattern name を返す
# ===========================================================================

@test "input-waiting-detection: Menu UI - 'Enter to select' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "  Enter to select"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"menu_enter_select"* ]]
}

@test "input-waiting-detection: Menu UI - '↑/↓ to navigate' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "↑/↓ to navigate, Enter to confirm"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"menu_arrow_navigate"* ]]
}

@test "input-waiting-detection: Menu UI - '❯ 1.' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "❯ 1. オプション A"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"menu_prompt_number"* ]]
}

# ===========================================================================
# Free-form text パターン検知
# Scenario: Free-form text パターンを検知する
# WHEN pane_output に自然言語確認フレーズを含む行があるとき
# THEN detect_input_waiting は非空の pattern name を返す
# ===========================================================================

@test "input-waiting-detection: Free-form - 'よろしいですか？' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "この変更でよろしいですか？"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"freeform_yoroshii"* ]]
}

@test "input-waiting-detection: Free-form - '続けますか？' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "このまま続けますか？"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"freeform_tsuzukemasu"* ]]
}

@test "input-waiting-detection: Free-form - '[y/N]' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "削除を実行しますか [y/N]:"

  assert_success
  [ -n "$output" ]
  [[ "$output" == *"freeform_yn_bracket"* ]]
}

# ===========================================================================
# Wave 7 #470 再現パターン
# Scenario: Wave 7 #470 再現パターンを検知する
# WHEN pane_output に「このまま実装に進んでよいですか？」を含むとき
# THEN detect_input_waiting は free-form pattern name を返す
# ===========================================================================

@test "input-waiting-detection: Wave 7 再現 - 'このまま実装に進んでよいですか？' を検知する" {
  _setup_detect_script

  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "このまま実装に進んでよいですか？"

  assert_success
  [ -n "$output" ]
  # "進んでよいですか" は freeform_tsuzukemasu パターンにマッチする
  [[ "$output" == *"freeform_tsuzukemasu"* ]]
}

# ===========================================================================
# デバウンス検証
# Scenario: 1 回目検知では state 書き込みをスキップする
# Scenario: 2 回目検知で state 書き込みを確定する
# ===========================================================================

@test "input-waiting-detection: デバウンス - 1 回目は state 未書き込み" {
  _setup_detect_script

  SEEN_FILE="$SANDBOX/seen-patterns.txt"
  STATE_WRITE_LOG="$SANDBOX/state-write-debounce.txt"
  touch "$SEEN_FILE"

  # 1 回目実行: stdout は空、STATE_WRITE_LOG は作成されない
  SEEN_FILE="$SEEN_FILE" STATE_WRITE_LOG="$STATE_WRITE_LOG" \
    run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
      --pane-output "Enter to select" \
      --issue 510

  assert_success
  # stdout は空（state write しない）
  [ -z "$output" ]
  # STATE_WRITE_LOG は書き込まれていない
  [ ! -f "$STATE_WRITE_LOG" ]
  # SEEN_FILE に記録されている
  grep -q "510:menu_enter_select" "$SEEN_FILE"
}

@test "input-waiting-detection: デバウンス - 2 回目で state write 確定" {
  _setup_detect_script

  SEEN_FILE="$SANDBOX/seen-patterns-2nd.txt"
  STATE_WRITE_LOG="$SANDBOX/state-write-debounce-2nd.txt"

  # SEEN_FILE に既存エントリを事前登録（1 回目済み状態）
  echo "510:menu_enter_select" > "$SEEN_FILE"

  # 2 回目実行: stdout に pattern name、STATE_WRITE_LOG に記録
  SEEN_FILE="$SEEN_FILE" STATE_WRITE_LOG="$STATE_WRITE_LOG" \
    run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
      --pane-output "Enter to select" \
      --issue 510

  assert_success
  # stdout に pattern name が返る
  [ -n "$output" ]
  [[ "$output" == *"menu_enter_select"* ]]
  # STATE_WRITE_LOG に state write が記録されている
  [ -f "$STATE_WRITE_LOG" ]
  grep -q "input_waiting_detected=menu_enter_select" "$STATE_WRITE_LOG"
}

# ===========================================================================
# False positive 非検知
# Scenario: chain 進捗キーワードのみでは false trigger しない
# WHEN pane_output が chain 進捗キーワードのみを含むとき
# THEN detect_input_waiting は空文字を返す
# ===========================================================================

@test "input-waiting-detection: false positive - chain 進捗キーワードのみで false trigger しない" {
  _setup_detect_script

  # chain 進捗のみを含む出力（input-waiting パターンなし）
  run bash "$SANDBOX/scripts/detect-input-waiting.sh" \
    --pane-output "setup chain 完了
>>> 提案完了
Phase 3 running
chain step 2/5 OK"

  assert_success
  # stdout は空（未検知）
  [ -z "$output" ]
}
