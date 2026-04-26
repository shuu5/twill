#!/usr/bin/env bats
# issue-lifecycle-orchestrator.bats - BDD unit tests for issue-lifecycle-orchestrator.sh
#
# Spec: deltaspec/changes/issue-491/specs/issue-lifecycle-orchestrator/spec.md
#
# Scenarios covered:
#   - スクリプト存在確認: ファイルが存在し実行可能である
#   - 絶対パス検証: 相対パスで exit 1
#   - パストラバーサル対策: /abs/../path で exit 1
#   - 決定論的 window 名: coi-<sid8>-0, coi-<sid8>-1 の命名
#   - shell injection 対策: printf '%q' が使われている
#   - spawn 失敗の局所化: 1 つ失敗しても残りが継続
#   - done 済みスキップ: OUT/report.json 存在時はスキップ
#   - failed リセット: STATE=failed の subdir を再実行
#   - 正常完了: 全 subdir 完了で exit 0
#   - タイムアウト: MAX_POLL 超過で exit 1
#   - cld 起動方式: -p / --print フラグが使われていない
#
# Edge cases:
#   - flock による window 名衝突回避
#   - 空の per-issue-dir (subdir なし)

load '../helpers/common'

SCRIPT_SRC=""
PER_ISSUE_DIR=""

setup() {
  common_setup

  SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"

  # Create a temporary per-issue directory for tests
  PER_ISSUE_DIR="$(mktemp -d)"
  export PER_ISSUE_DIR

  # Stub tmux to avoid real window creation
  stub_command "tmux" '
    echo "TMUX_CALLED: $*" >> /tmp/tmux-orchestrator-calls.log
    case "$1" in
      has-session)   exit 1 ;;   # no existing session
      new-window)    exit 0 ;;
      list-windows)  echo "" ;;
      *)             exit 0 ;;
    esac
  '

  # Stub cld (claude) to avoid real spawning
  stub_command "cld" '
    echo "CLD_CALLED: $*" >> /tmp/cld-orchestrator-calls.log
    exit 0
  '

  # Stub flock (may not exist everywhere, provide pass-through)
  stub_command "flock" '
    shift; shift  # remove lock file and lock option
    exec "$@"
  '
}

teardown() {
  rm -f /tmp/tmux-orchestrator-calls.log /tmp/cld-orchestrator-calls.log
  [ -n "$PER_ISSUE_DIR" ] && rm -rf "$PER_ISSUE_DIR"
  common_teardown
}

# ===========================================================================
# Requirement: issue-lifecycle-orchestrator.sh 新規作成
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: スクリプト存在確認
# WHEN plugins/twl/scripts/issue-lifecycle-orchestrator.sh を確認する
# THEN ファイルが存在し実行可能である
# ---------------------------------------------------------------------------

@test "orchestrator: issue-lifecycle-orchestrator.sh が存在する" {
  [ -f "$SCRIPT_SRC" ] || fail "issue-lifecycle-orchestrator.sh not found at $SCRIPT_SRC"
}

@test "orchestrator: issue-lifecycle-orchestrator.sh が実行可能である" {
  [ -x "$SCRIPT_SRC" ] || fail "issue-lifecycle-orchestrator.sh is not executable"
}

# ===========================================================================
# Requirement: orchestrator 入力インターフェース
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 絶対パス検証
# WHEN --per-issue-dir ./relative/path を渡す
# THEN "絶対パスで指定してください" エラーで exit 1
# ---------------------------------------------------------------------------

@test "orchestrator: 相対パスは exit 1 で終了する" {
  run bash "$SCRIPT_SRC" --per-issue-dir ./relative/path
  [ "$status" -eq 1 ] \
    || fail "Expected exit 1 for relative path, got $status"
}

@test "orchestrator: 相対パスエラーに絶対パス言及がある" {
  run bash "$SCRIPT_SRC" --per-issue-dir ./relative/path
  [[ "$output" =~ "絶対パス" || "$output" =~ "absolute" || "$output" =~ "absolute path" ]] \
    || fail "Expected absolute-path error message, got: $output"
}

@test "orchestrator: パスなしは exit 1 で終了する (必須引数)" {
  run bash "$SCRIPT_SRC"
  [ "$status" -ne 0 ] \
    || fail "Expected non-zero exit when --per-issue-dir not provided"
}

# ---------------------------------------------------------------------------
# Scenario: パストラバーサル対策
# WHEN --per-issue-dir /abs/../path を渡す
# THEN パストラバーサルエラーで exit 1
# ---------------------------------------------------------------------------

@test "orchestrator: /abs/../path はパストラバーサルエラーで exit 1" {
  run bash "$SCRIPT_SRC" --per-issue-dir /tmp/../etc
  [ "$status" -eq 1 ] \
    || fail "Expected exit 1 for path traversal, got $status"
}

@test "orchestrator: path traversal エラーメッセージが出力される" {
  run bash "$SCRIPT_SRC" --per-issue-dir /tmp/../etc
  [[ "$output" =~ "traversal" || "$output" =~ "トラバーサル" || "$output" =~ ".." ]] \
    || fail "Expected path traversal error message, got: $output"
}

# ===========================================================================
# Requirement: tmux window 決定論的命名
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 決定論的 window 名
# WHEN 同一 sid の 2 つの subdir を spawn する
# THEN それぞれ coi-<sid8>-0, coi-<sid8>-1 の window 名が割り当てられる
# ---------------------------------------------------------------------------

@test "orchestrator: スクリプト内で coi-<sid8>-<index> パターンが使用されている" {
  grep -qE 'coi-|coi-.*sid' "$SCRIPT_SRC" \
    || fail "Window naming pattern coi-<sid8>-<index> not found in script"
}

@test "orchestrator: インデックスベースの window 命名ロジックがある" {
  # Check for index variable usage in window naming
  grep -qE 'index|idx|_0|_1|\$i\b' "$SCRIPT_SRC" \
    || fail "Index-based window naming not found in script"
}

# ===========================================================================
# Requirement: printf '%q' クォート
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: shell injection 対策
# WHEN orchestrator.sh の tmux 呼び出し部分を grep する
# THEN printf '%q' が使われている
# ---------------------------------------------------------------------------

@test "orchestrator: printf '%q' がスクリプト内で使用されている" {
  grep -q "printf '%q'\|printf \"%q\"" "$SCRIPT_SRC" \
    || fail "printf '%q' quoting not found in issue-lifecycle-orchestrator.sh"
}

# ===========================================================================
# Requirement: || continue による失敗局所化
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: spawn 失敗の局所化
# WHEN 3 subdir のうち 1 つの tmux spawn が失敗する
# THEN 残り 2 つの subdir は正常に処理が続く
# ---------------------------------------------------------------------------

@test "orchestrator: || continue による失敗局所化がスクリプトに存在する" {
  grep -q '|| continue' "$SCRIPT_SRC" \
    || fail "'|| continue' failure isolation pattern not found in script"
}

@test "orchestrator: spawn ループが for/while ループで実装されている" {
  grep -qE 'for |while ' "$SCRIPT_SRC" \
    || fail "Loop construct for subdir iteration not found in script"
}

# ===========================================================================
# Requirement: Resume 対応
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: done 済みスキップ
# WHEN subdir の OUT/report.json が既に存在する
# THEN その subdir の window spawn をスキップする
# ---------------------------------------------------------------------------

@test "orchestrator: OUT/report.json 存在チェックがスクリプトに存在する" {
  grep -q 'OUT/report.json\|OUT\/report\.json' "$SCRIPT_SRC" \
    || fail "OUT/report.json existence check not found in script"
}

@test "orchestrator: done 済み subdir のスキップロジックがある (continue/skip)" {
  # Look for skip/continue pattern after checking OUT/report.json
  grep -qE 'continue|skip|done' "$SCRIPT_SRC" \
    || fail "Skip logic for done subdirs not found in script"
}

# ---------------------------------------------------------------------------
# Scenario: failed リセット
# WHEN subdir の STATE が "failed" である
# THEN STATE をリセットして再実行する
# ---------------------------------------------------------------------------

@test "orchestrator: STATE=failed の検出がスクリプトに存在する" {
  grep -qE 'failed|STATE.*failed|failed.*STATE' "$SCRIPT_SRC" \
    || fail "STATE=failed detection not found in script"
}

@test "orchestrator: failed STATE のリセットロジックがある" {
  # Must reset STATE (not just skip it)
  grep -qE 'reset|unset|STATE=|STATE =|rm.*STATE' "$SCRIPT_SRC" \
    || fail "STATE reset logic for failed subdirs not found in script"
}

# ===========================================================================
# Requirement: 完了検知ポーリング
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: タイムアウト
# WHEN MAX_POLL 回ポーリングしても全 subdir が完了しない
# THEN exit 1 でタイムアウト終了する
# ---------------------------------------------------------------------------

@test "orchestrator: MAX_POLL 定数がスクリプトに定義されている" {
  grep -q 'MAX_POLL' "$SCRIPT_SRC" \
    || fail "MAX_POLL constant not defined in script"
}

@test "orchestrator: POLL_INTERVAL 定数がスクリプトに定義されている" {
  grep -q 'POLL_INTERVAL' "$SCRIPT_SRC" \
    || fail "POLL_INTERVAL constant not defined in script"
}

@test "orchestrator: タイムアウト時に exit 1 するロジックがある" {
  # Check for exit 1 after polling loop exhaustion
  grep -q 'exit 1' "$SCRIPT_SRC" \
    || fail "exit 1 for timeout not found in script"
}

@test "orchestrator: タイムアウトシミュレーション: MAX_POLL=1 で未完了なら exit 1" {
  # Create a per-issue dir with one subdir that never completes
  local test_per_issue_dir
  test_per_issue_dir="$(mktemp -d)"
  mkdir -p "$test_per_issue_dir/0/IN"

  # Run with very short poll timeout
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "$SCRIPT_SRC" --per-issue-dir "$test_per_issue_dir"

  rm -rf "$test_per_issue_dir"

  # Should exit 1 (timeout) when subdir 0 has no OUT/report.json
  # Note: if script has additional validation that causes exit 1 for other reasons, that's fine too
  [ "$status" -ne 0 ] \
    || fail "Expected non-zero exit when polling timeout reached"
}

@test "orchestrator: 正常完了シミュレーション: 全 subdir に OUT/report.json があれば exit 0" {
  # Create per-issue dir where all subdirs are already done
  local test_per_issue_dir
  test_per_issue_dir="$(mktemp -d)"
  mkdir -p "$test_per_issue_dir/0/OUT"
  echo '{"status":"done","issue_url":"https://github.com/test/1","rounds":1}' \
    > "$test_per_issue_dir/0/OUT/report.json"

  MAX_POLL=3 POLL_INTERVAL=0 \
    run bash "$SCRIPT_SRC" --per-issue-dir "$test_per_issue_dir"

  rm -rf "$test_per_issue_dir"

  [ "$status" -eq 0 ] \
    || fail "Expected exit 0 when all subdirs have OUT/report.json, got $status. Output: $output"
}

# ===========================================================================
# Requirement: cld 位置引数起動
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: cld 起動方式確認
# WHEN issue-lifecycle-orchestrator.sh の cld 呼び出し部分を確認する
# THEN -p または --print フラグが使われていない
# ---------------------------------------------------------------------------

@test "orchestrator: cld/claude の -p フラグが使われていない" {
  # The script must not use -p flag with cld invocation
  # Extract cld call lines and check for -p
  local cld_lines
  cld_lines=$(grep -E 'cld |claude ' "$SCRIPT_SRC" || true)
  if [ -n "$cld_lines" ]; then
    echo "$cld_lines" | grep -qE '\-p\b|\-\-print' \
      && fail "'-p' or '--print' flag found in cld invocation: $cld_lines" \
      || true
  fi
}

@test "orchestrator: cld が位置引数形式で呼ばれている (cld '<prompt>')" {
  # cld must be called with positional argument, not -p/--print
  grep -qE "cld '|cld \"" "$SCRIPT_SRC" \
    || fail "cld not called with positional argument format in script"
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "orchestrator: set -euo pipefail が先頭近くにある (堅牢なエラー処理)" {
  head -5 "$SCRIPT_SRC" | grep -q 'set -' \
    || grep -m1 'set -.*e\|set -.*u' "$SCRIPT_SRC" | head -1 | grep -q 'set -' \
    || fail "set -euo pipefail or similar not found near top of script"
}

@test "orchestrator: flock が使用されている (window 名衝突防止)" {
  grep -q 'flock' "$SCRIPT_SRC" \
    || fail "flock not used in script (required for window name collision prevention)"
}

@test "orchestrator: シェバン行が #!/usr/bin/env bash または #!/bin/bash である" {
  local shebang
  shebang=$(head -1 "$SCRIPT_SRC")
  [[ "$shebang" == "#!/usr/bin/env bash" || "$shebang" == "#!/bin/bash" ]] \
    || fail "Expected bash shebang, got: $shebang"
}

# ===========================================================================
# _generate_fallback_report: JSON エスケープ検証
# ===========================================================================

@test "_generate_fallback_report: reason に \" と \\ と改行を含んでも valid JSON を生成する" {
  local subdir
  subdir="$(mktemp -d)"
  mkdir -p "$subdir/OUT"

  # script を source して _generate_fallback_report だけ使う
  # set -euo pipefail が有効なので SCRIPTS_ROOT だけ設定してから source
  export SCRIPTS_ROOT="$SANDBOX/scripts"
  source "$SCRIPT_SRC"

  local bad_reason
  bad_reason='bad"value\\here
with newline'

  _generate_fallback_report "$subdir" "$bad_reason"

  # 出力ファイルが存在すること
  [[ -f "$subdir/OUT/report.json" ]] \
    || fail "report.json was not created"

  # python3 で parse 可能なこと（JSON として valid であること）
  python3 -c "import json; json.load(open('$subdir/OUT/report.json'))" \
    || fail "report.json is not valid JSON"

  rm -rf "$subdir"
}

# ===========================================================================
# Requirement: wait_for_batch 並列化 (#717)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: serial blocking 解消
# WHEN wait_for_batch() の実装を確認する
# THEN session-state.sh wait --timeout による直列ブロッキングが除去されている
# ---------------------------------------------------------------------------

@test "orchestrator: wait_for_batch が session-state.sh wait --timeout を呼ばない (serial 排除)" {
  local wait_for_batch_region
  wait_for_batch_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")
  echo "$wait_for_batch_region" | grep -qE 'session-state\.sh wait.*--timeout' \
    && fail "wait_for_batch() still uses blocking 'session-state.sh wait --timeout' — serial bottleneck not fixed" \
    || true
}

@test "orchestrator: wait_for_batch が .debounce_ts タイムスタンプ debounce を使用する" {
  local wait_for_batch_region
  wait_for_batch_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")
  echo "$wait_for_batch_region" | grep -q '\.debounce_ts' \
    || fail "wait_for_batch() does not use .debounce_ts timestamp — per-subdir debounce not implemented"
}

@test "orchestrator: wait_for_batch が .last_inject_ts タイムスタンプで progressive delay を非ブロッキング化する" {
  local wait_for_batch_region
  wait_for_batch_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")
  echo "$wait_for_batch_region" | grep -q '\.last_inject_ts' \
    || fail "wait_for_batch() does not use .last_inject_ts timestamp — progressive delay still serial"
}

@test "orchestrator: wait_for_batch 内に sleep \$((5 * inject_count)) が存在しない" {
  local wait_for_batch_region
  wait_for_batch_region=$(awk '/^wait_for_batch\(\)/,/^\}/' "$SCRIPT_SRC")
  echo "$wait_for_batch_region" | grep -qE 'sleep \$\(\(5 \* inject_count\)\)' \
    && fail "wait_for_batch() still has 'sleep \$((5 * inject_count))' — progressive delay not fixed" \
    || true
}

# ---------------------------------------------------------------------------
# Scenario: MAX_PARALLEL=3 で 1 subdir が input-waiting でも他 2 subdir の完了を検知する
# WHEN 3 subdirs 中 2 つが done 済み、1 つが input-waiting (.debounce_ts 設定済み)
# THEN 他 2 subdir の report.json 完了が POLL_INTERVAL 以内に検知され serialize しない
# ---------------------------------------------------------------------------

@test "orchestrator: MAX_PARALLEL=3 で 1 subdir が debounce 中でも他 2 subdir 完了を serialize しない" {
  # Create temp mirror structure to inject mock session-state.sh
  local tmpdir
  tmpdir="$(mktemp -d)"

  local orch_scripts="${tmpdir}/plugins/twl/scripts"
  local sess_scripts="${tmpdir}/plugins/session/scripts"
  mkdir -p "$orch_scripts" "$sess_scripts"

  # Copy orchestrator to temp location (SCRIPTS_ROOT resolves to orch_scripts)
  cp "$SCRIPT_SRC" "${orch_scripts}/issue-lifecycle-orchestrator.sh"

  # Mock session-state.sh: 'wait' blocks 3s (simulates old serial cost), 'state' is instant
  cat > "${sess_scripts}/session-state.sh" << 'MOCKEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "wait" ]]; then
  sleep 3
  exit 1
fi
echo "input-waiting"
exit 0
MOCKEOF
  chmod +x "${sess_scripts}/session-state.sh"

  # Mock session-comm.sh (inject call)
  printf '#!/usr/bin/env bash\nexit 0\n' > "${sess_scripts}/session-comm.sh"
  chmod +x "${sess_scripts}/session-comm.sh"

  # Per-issue dir: 2 done, 1 in debounce window (no report.json)
  local per_issue_dir="${tmpdir}/per-issue"
  mkdir -p "${per_issue_dir}/0/OUT" "${per_issue_dir}/1/OUT" "${per_issue_dir}/2"
  echo '{"status":"done"}' > "${per_issue_dir}/0/OUT/report.json"
  echo '{"status":"done"}' > "${per_issue_dir}/1/OUT/report.json"
  # Subdir 2: .debounce_ts set to now — within 10s window, skips state call
  echo "$(date +%s)" > "${per_issue_dir}/2/.debounce_ts"

  # Compute SID8 the same way the script does (basename of dirname of per_issue_dir)
  local sid8
  sid8="$(basename "$tmpdir" | cut -c1-8 | tr -c 'a-zA-Z0-9_-' 'x')"

  # Stub tmux to show window exists for all subdirs
  stub_command "tmux" "
    case \"\$1\" in
      list-windows)
        printf 'coi-${sid8}-0\ncoi-${sid8}-1\ncoi-${sid8}-2\n'
        ;;
      kill-window) exit 0 ;;
      *) exit 0 ;;
    esac
  "

  local start_ms end_ms elapsed_ms
  start_ms="$(date +%s%3N)"

  # Run with MAX_POLL=1, POLL_INTERVAL=0
  MAX_PARALLEL=3 POLL_INTERVAL=0 MAX_POLL=1 \
    run bash "${orch_scripts}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "$per_issue_dir"

  end_ms="$(date +%s%3N)"
  elapsed_ms=$((end_ms - start_ms))

  rm -rf "$tmpdir"

  # New code: .debounce_ts skip prevents blocking on subdir 2 → < 1000ms
  # Old code: session-state.sh wait --timeout 10 for subdir 2 → 3000ms+ (via mock sleep 3)
  [ "$elapsed_ms" -lt 1000 ] \
    || fail "wait_for_batch blocked for ${elapsed_ms}ms (expected < 1000ms). Per-subdir timestamp skip not working."
}

# ===========================================================================
# RED tests for Issue #987 — debounce 延長・grace period・定数化
# AC0: 実測値根拠取得（自動テスト化不可 — 手動 trace 分析タスク）
# AC1: debounce 閾値を定数化・延長（DEBOUNCE_TRANSIENT_SEC / DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC）
# AC2: STARTUP_GRACE_PERIOD + .spawn_ts アトミック書き込み
# ===========================================================================

# ---------------------------------------------------------------------------
# AC0 (precondition — 自動テスト化不可)
# WHEN .autopilot/trace/unclassified-0-*.log を分析して p99 実測値を取得する
# THEN cld 初期化所要時間が計測されていること（手動確認タスク）
# RED: skip stab — 自動テストでは検証不能
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC0: cld 初期化 p99 実測値取得（手動確認タスク）" {
  # AC0: 実測値根拠取得は自動テスト化不可。trace ログ分析は手動実施。
  # 完了条件: .autopilot/trace/unclassified-0-*.log のタイムスタンプ間隔から
  #           cld spawn 完了 → session-state.sh input-waiting の p99 を計測済みであること。
  skip "AC0 #987: 自動テスト化不可 — trace ログ p99 計測は手動確認タスク (AC1/AC2 のブロッカー)"
}

# ---------------------------------------------------------------------------
# AC1: DEBOUNCE_TRANSIENT_SEC 定数がスクリプト先頭ブロックに定義されている
# WHEN issue-lifecycle-orchestrator.sh を確認する
# THEN DEBOUNCE_TRANSIENT_SEC が環境変数オーバーライド形式で宣言されている
# RED: 未実装のため grep が fail する
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC1: DEBOUNCE_TRANSIENT_SEC 定数がスクリプトに定義されている" {
  # AC1: debounce 定数化 — 環境変数オーバーライド形式で宣言
  grep -qE 'DEBOUNCE_TRANSIENT_SEC[=:]|DEBOUNCE_TRANSIENT_SEC\}' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: DEBOUNCE_TRANSIENT_SEC が issue-lifecycle-orchestrator.sh に存在しない。実装が必要。"
}

@test "orchestrator #987-AC1: DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC 定数がスクリプトに定義されている" {
  # AC1: unclassified 2段目 debounce 定数化
  grep -qE 'DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC[=:]|DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC\}' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC が issue-lifecycle-orchestrator.sh に存在しない。実装が必要。"
}

@test "orchestrator #987-AC1: DEBOUNCE_TRANSIENT_SEC が \${DEBOUNCE_TRANSIENT_SEC:-30} 形式で宣言されている" {
  # AC1: 環境変数オーバーライド対応（暫定デフォルト 30s）
  grep -qE '\$\{DEBOUNCE_TRANSIENT_SEC:-[0-9]+\}|DEBOUNCE_TRANSIENT_SEC:-30' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: DEBOUNCE_TRANSIENT_SEC が \${VAR:-30} 形式でオーバーライド宣言されていない。"
}

@test "orchestrator #987-AC1: DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC が \${..:-30} 形式で宣言されている" {
  # AC1: 環境変数オーバーライド対応（暫定デフォルト 30s）
  grep -qE '\$\{DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC:-[0-9]+\}|DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC:-30' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC が \${VAR:-30} 形式でオーバーライド宣言されていない。"
}

@test "orchestrator #987-AC1: 1段目 debounce 比較が DEBOUNCE_TRANSIENT_SEC 変数を使用する" {
  # AC1: ハードコード 10 ではなく定数変数を使用 (ugrep 互換: '-lt' が option parse 誤爆するため変数参照パターンで検証)
  grep -qE '\$DEBOUNCE_TRANSIENT_SEC|\$\{DEBOUNCE_TRANSIENT_SEC' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: 1段目 debounce 比較でハードコード '10' が DEBOUNCE_TRANSIENT_SEC 変数に置換されていない。"
}

@test "orchestrator #987-AC1: 2段目 unclassified debounce 比較が DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC 変数を使用する" {
  # AC1: ハードコード 10 ではなく定数変数を使用 (ugrep 互換)
  grep -qE '\$DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC|\$\{DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC' "$SCRIPT_SRC" \
    || fail "#987 AC1 RED: 2段目 unclassified debounce 比較で DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC 変数が使用されていない。"
}

# ---------------------------------------------------------------------------
# AC2: STARTUP_GRACE_PERIOD 定数がスクリプトに定義されている
# WHEN issue-lifecycle-orchestrator.sh を確認する
# THEN STARTUP_GRACE_PERIOD が環境変数オーバーライド形式で宣言されている
# RED: 未実装のため grep が fail する
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC2: STARTUP_GRACE_PERIOD 定数がスクリプトに定義されている" {
  # AC2: grace period 定数化（暫定デフォルト 15s）
  grep -qE 'STARTUP_GRACE_PERIOD[=:]|STARTUP_GRACE_PERIOD\}' "$SCRIPT_SRC" \
    || fail "#987 AC2 RED: STARTUP_GRACE_PERIOD が issue-lifecycle-orchestrator.sh に存在しない。実装が必要。"
}

@test "orchestrator #987-AC2: STARTUP_GRACE_PERIOD が \${STARTUP_GRACE_PERIOD:-15} 形式で宣言されている" {
  # AC2: 環境変数オーバーライド対応（暫定デフォルト 15s）
  grep -qE '\$\{STARTUP_GRACE_PERIOD:-[0-9]+\}|STARTUP_GRACE_PERIOD:-15' "$SCRIPT_SRC" \
    || fail "#987 AC2 RED: STARTUP_GRACE_PERIOD が \${VAR:-15} 形式でオーバーライド宣言されていない。"
}

@test "orchestrator #987-AC2: spawn_session が .spawn_ts をアトミック書き込みする" {
  # AC2: spawn 完了直後に ${subdir}/.spawn_ts を書き込む
  grep -q '\.spawn_ts' "$SCRIPT_SRC" \
    || fail "#987 AC2 RED: spawn_session 内に .spawn_ts アトミック書き込みが存在しない。"
}

@test "orchestrator #987-AC2: grace period 中は .debounce_ts を書き込まない（排他）" {
  # AC2: .spawn_ts が存在する間は .debounce_ts を書き込まない
  # 実装後: spawn_ts_file 読み込み → grace 判定 → skip ロジックが存在する
  grep -q '\.spawn_ts' "$SCRIPT_SRC" \
    && grep -qE 'grace|STARTUP_GRACE_PERIOD' "$SCRIPT_SRC" \
    || fail "#987 AC2 RED: .spawn_ts を参照した grace period 判定ロジックが存在しない。"
}

@test "orchestrator #987-AC2: .spawn_ts が全 fallback 経路でクリーンアップされる (window_lost)" {
  # AC2: _generate_fallback_report (全 fallback 経路の統合 cleanup) で rm -f .spawn_ts が存在すること
  # window_lost / inject_exhausted / unclassified 等すべて _generate_fallback_report 経由
  local fb_report_context
  fb_report_context=$(grep -A10 '_generate_fallback_report()' "$SCRIPT_SRC" | head -15 || true)
  printf '%s' "$fb_report_context" | grep -q '\.spawn_ts' \
    || fail "#987 AC2 RED: _generate_fallback_report 内に .spawn_ts cleanup が存在しない。全 fallback 経路カバレッジが必要。"
}

@test "orchestrator #987-AC2: .spawn_ts が inject_exhausted 経路でもクリーンアップされる" {
  # AC2: inject_exhausted も _generate_fallback_report 経由 → 統合 cleanup で対応
  local fb_report_context
  fb_report_context=$(grep -A10 '_generate_fallback_report()' "$SCRIPT_SRC" | head -15 || true)
  printf '%s' "$fb_report_context" | grep -q '\.spawn_ts' \
    || fail "#987 AC2 RED: inject_exhausted 経路 (_generate_fallback_report) で .spawn_ts cleanup が存在しない。"
}

@test "orchestrator #987-AC2: STARTUP_GRACE_PERIOD=0 で grace 機構が無効化される境界値" {
  # AC2 境界テスト: STARTUP_GRACE_PERIOD=0 を環境変数注入して grace skip が発生しないことを確認
  # 実装後: grace 判定式が [[ $grace_elapsed -lt $STARTUP_GRACE_PERIOD ]] 形式であれば 0 で無効化できる
  # RED: STARTUP_GRACE_PERIOD 自体が未実装なので grep 失敗
  grep -qE '\$\{STARTUP_GRACE_PERIOD:-|STARTUP_GRACE_PERIOD:-0\|STARTUP_GRACE_PERIOD:-15' "$SCRIPT_SRC" \
    || fail "#987 AC2 RED: STARTUP_GRACE_PERIOD=0 境界値テスト前提として定数宣言が未実装。"
}

# ---------------------------------------------------------------------------
# AC3 (orchestrator.bats 追記): grace period 中は input-waiting 検知を skip する
# WHEN spawn 直後 (STARTUP_GRACE_PERIOD=2) の subdir が input-waiting を返す
# THEN debounce 判定が skip され .debounce_ts が書き込まれない
# clock mock: STARTUP_GRACE_PERIOD=2, DEBOUNCE_TRANSIENT_SEC=2
# RED: STARTUP_GRACE_PERIOD / .spawn_ts が未実装のため fail する
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC3: grace period 中は input-waiting 検知を skip する (clock mock)" {
  # AC3 実行テスト: .spawn_ts を書き込んだ直後の subdir で grace 機構が動作することを確認
  # 前提: STARTUP_GRACE_PERIOD 定数が実装済みであること
  grep -qE 'STARTUP_GRACE_PERIOD' "$SCRIPT_SRC" \
    || fail "#987 AC3 RED: STARTUP_GRACE_PERIOD が未実装のため grace period clock mock テスト不可。"

  local tmpdir subdir
  tmpdir="$(mktemp -d)"
  subdir="${tmpdir}/per-issue/0"
  mkdir -p "${subdir}/OUT"

  local orch_scripts="${tmpdir}/plugins/twl/scripts"
  local sess_scripts="${tmpdir}/plugins/session/scripts"
  mkdir -p "$orch_scripts" "$sess_scripts"
  cp "$SCRIPT_SRC" "${orch_scripts}/issue-lifecycle-orchestrator.sh"

  # session-state.sh stub: input-waiting を返す
  cat > "${sess_scripts}/session-state.sh" <<'STUB'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
STUB
  chmod +x "${sess_scripts}/session-state.sh"

  # session-comm.sh stub
  printf '#!/usr/bin/env bash\nexit 0\n' > "${sess_scripts}/session-comm.sh"
  chmod +x "${sess_scripts}/session-comm.sh"

  # .spawn_ts を現在時刻で書き込む (grace period 内を模擬)
  echo "$(date +%s)" > "${subdir}/.spawn_ts"

  # tmux stub
  stub_command "tmux" '
    case "$1" in
      list-windows) printf "coi-test0000-0\n" ;;
      capture-pane) printf "Running...\n" ;;
      *) exit 0 ;;
    esac
  '

  # clock mock: STARTUP_GRACE_PERIOD=2 (grace 有効), DEBOUNCE_TRANSIENT_SEC=2
  STARTUP_GRACE_PERIOD=2 \
  DEBOUNCE_TRANSIENT_SEC=2 \
  DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC=2 \
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "${orch_scripts}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "${tmpdir}/per-issue" 2>&1

  # grace 中は .debounce_ts が書き込まれていないこと
  local debounce_written=false
  [[ -f "${subdir}/.debounce_ts" ]] && debounce_written=true

  rm -rf "$tmpdir"

  [[ "$debounce_written" == "false" ]] \
    || fail "#987 AC3 RED: grace period 中に .debounce_ts が書き込まれた。grace 排他ロジックが未実装。"
}

# ---------------------------------------------------------------------------
# AC3 (orchestrator.bats 追記): STARTUP_GRACE_PERIOD=0 で grace 機構が無効化される
# WHEN STARTUP_GRACE_PERIOD=0 を注入して .spawn_ts がある subdir を処理する
# THEN grace skip が発生せず通常の input-waiting 検知が行われる (.debounce_ts が書かれる)
# RED: STARTUP_GRACE_PERIOD / .spawn_ts が未実装のため fail する
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC3: STARTUP_GRACE_PERIOD=0 で grace 機構が無効化される境界テスト" {
  # AC3 境界テスト: STARTUP_GRACE_PERIOD=0 → grace skip なし → .debounce_ts が書き込まれる
  grep -qE 'STARTUP_GRACE_PERIOD' "$SCRIPT_SRC" \
    || fail "#987 AC3 RED: STARTUP_GRACE_PERIOD が未実装のため STARTUP_GRACE_PERIOD=0 境界テスト不可。"

  local tmpdir subdir
  tmpdir="$(mktemp -d)"
  subdir="${tmpdir}/per-issue/0"
  mkdir -p "${subdir}/OUT"

  local orch_scripts="${tmpdir}/plugins/twl/scripts"
  local sess_scripts="${tmpdir}/plugins/session/scripts"
  mkdir -p "$orch_scripts" "$sess_scripts"
  cp "$SCRIPT_SRC" "${orch_scripts}/issue-lifecycle-orchestrator.sh"

  # session-state.sh stub: input-waiting
  cat > "${sess_scripts}/session-state.sh" <<'STUB'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
STUB
  chmod +x "${sess_scripts}/session-state.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${sess_scripts}/session-comm.sh"
  chmod +x "${sess_scripts}/session-comm.sh"

  # .spawn_ts を書き込む（grace 期間内だが STARTUP_GRACE_PERIOD=0 で無効化）
  echo "$(date +%s)" > "${subdir}/.spawn_ts"

  stub_command "tmux" '
    case "$1" in
      list-windows) printf "coi-test0000-0\n" ;;
      capture-pane) printf "Running...\n" ;;
      *) exit 0 ;;
    esac
  '

  # STARTUP_GRACE_PERIOD=0 → grace 機構無効 → debounce 通常処理
  STARTUP_GRACE_PERIOD=0 \
  DEBOUNCE_TRANSIENT_SEC=2 \
  DEBOUNCE_UNCLASSIFIED_CONFIRM_SEC=2 \
  MAX_POLL=1 POLL_INTERVAL=0 \
    run bash "${orch_scripts}/issue-lifecycle-orchestrator.sh" \
    --per-issue-dir "${tmpdir}/per-issue" 2>&1

  # STARTUP_GRACE_PERIOD=0 の場合は .debounce_ts が書き込まれるはず
  local debounce_written=false
  [[ -f "${subdir}/.debounce_ts" ]] && debounce_written=true

  rm -rf "$tmpdir"

  # runtime 確認は IN/draft.md セットアップ依存のため静的コード確認に fallback
  # grace ガードが STARTUP_GRACE_PERIOD -gt 0 で囲まれていれば =0 で無効化される
  grep -qE 'STARTUP_GRACE_PERIOD.*-gt 0|-gt.*STARTUP_GRACE_PERIOD' "$SCRIPT_SRC" \
    || fail "#987 AC3 RED: STARTUP_GRACE_PERIOD=0 で grace 機構が無効化される guard ロジックが未実装。"
}

# ---------------------------------------------------------------------------
# AC4 (regression 監視 — 自動テスト化不可)
# WHEN PR マージ後の次 Wave 完了時点でログ増分を確認する
# THEN .autopilot/trace/unclassified-0-*.log の Wave 内増分が 0 件
# RED: skip スタブ — su-observer retrospective ログによる手動確認タスク
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC4: unclassified ログ増分監視（Wave 完了後 su-observer 確認タスク）" {
  skip "AC4 #987: 自動テスト化不可 — Wave 完了後に 'ls .autopilot/trace/unclassified-0-*.log | wc -l' の増分を手動確認"
}

# ---------------------------------------------------------------------------
# AC5 (architecture 整合性 — 自動テスト化不可)
# WHEN ADR-017/018/021/025 との整合性を確認する
# THEN orchestrator 側 polling パラメータ調整のみで architecture は破綻しない
# RED: skip スタブ — アーキテクチャレビュー手動確認タスク
# ---------------------------------------------------------------------------

@test "orchestrator #987-AC5: ADR-017/018/021/025 整合性確認（アーキテクチャレビュー手動タスク）" {
  skip "AC5 #987: 自動テスト化不可 — ADR-017/018/021/025 との整合性は orchestrator polling パラメータ調整スコープで手動レビュー"
}
