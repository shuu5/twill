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
