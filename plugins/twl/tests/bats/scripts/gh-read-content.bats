#!/usr/bin/env bats
# gh-read-content.bats - unit tests for scripts/lib/gh-read-content.sh
#
# Issue #499: gh-read-content ヘルパー新設
# Spec: deltaspec/changes/issue-499/specs/gh-read-content/spec.md
#
# Tested functions:
#   gh_read_issue_full <issue_num> [--repo <owner/repo>]
#     - body + "## === Comments ===" セパレータ + 全 comments を標準出力
#     - 切り詰めなし、--repo フラグで cross-repo 対応
#     - 失敗時は空文字列を返し stderr に警告
#
#   gh_read_pr_full <pr_num> [--repo <owner/repo>]
#     - PR body + "## === Comments ===" セパレータ + 全 comments を標準出力
#     - 同上フォールバック仕様
#
# Test strategy: gh CLI を STUB_BIN に差し替え、環境変数で挙動を制御する。
#   GH_ISSUE_BODY     - issue view --json body の body フィールド値（デフォルト: "Issue body text"）
#   GH_ISSUE_COMMENTS - issue view --json comments の comments JSON（デフォルト: 2件）
#   GH_PR_BODY        - pr view --json body の body フィールド値
#   GH_PR_COMMENTS    - pr view --json comments の comments JSON
#   GH_FAIL_BODY      - non-empty 時 body 取得で exit 1
#   GH_FAIL_COMMENTS  - non-empty 時 comments 取得で exit 1
#   GH_CALLS_LOG      - 呼び出し記録ファイル（省略時 /dev/null）

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  HELPER_SH="$REPO_ROOT_REAL/scripts/lib/gh-read-content.sh"

  SANDBOX="$(mktemp -d)"
  export SANDBOX

  STUB_BIN="$SANDBOX/.stub-bin"
  mkdir -p "$STUB_BIN"

  GH_CALLS_LOG="$SANDBOX/gh-calls.log"
  export GH_CALLS_LOG

  # gh stub: routes based on subcommand and flags
  cat > "$STUB_BIN/gh" <<'GH_STUB_EOF'
#!/usr/bin/env bash
# gh stub for gh-read-content tests
# Logs all args, then routes to appropriate response

echo "$*" >> "${GH_CALLS_LOG:-/dev/null}"

GH_FAIL_BODY="${GH_FAIL_BODY:-}"
GH_FAIL_COMMENTS="${GH_FAIL_COMMENTS:-}"

GH_ISSUE_BODY="${GH_ISSUE_BODY:-Issue body text}"
GH_ISSUE_COMMENTS="${GH_ISSUE_COMMENTS:-[{\"body\":\"First comment\"},{\"body\":\"Second comment\"}]}"
GH_PR_BODY="${GH_PR_BODY:-PR body text}"
GH_PR_COMMENTS="${GH_PR_COMMENTS:-[{\"body\":\"PR first comment\"},{\"body\":\"PR second comment\"}]}"

# Parse subcommand: issue | pr
subcmd="$1"
# Find --json field argument
json_field=""
for arg in "$@"; do
  case "$arg" in
    body|comments) json_field="$arg" ;;
  esac
done

if [[ "$subcmd" == "issue" ]]; then
  if [[ "$json_field" == "body" ]]; then
    if [[ -n "$GH_FAIL_BODY" ]]; then
      echo "gh: could not resolve to an issue" >&2
      exit 1
    fi
    printf '{"body":"%s"}' "$GH_ISSUE_BODY"
    exit 0
  elif [[ "$json_field" == "comments" ]]; then
    if [[ -n "$GH_FAIL_COMMENTS" ]]; then
      echo "gh: could not resolve to an issue" >&2
      exit 1
    fi
    printf '{"comments":%s}' "$GH_ISSUE_COMMENTS"
    exit 0
  fi
elif [[ "$subcmd" == "pr" ]]; then
  if [[ "$json_field" == "body" ]]; then
    if [[ -n "$GH_FAIL_BODY" ]]; then
      echo "gh: could not resolve to a PR" >&2
      exit 1
    fi
    printf '{"body":"%s"}' "$GH_PR_BODY"
    exit 0
  elif [[ "$json_field" == "comments" ]]; then
    if [[ -n "$GH_FAIL_COMMENTS" ]]; then
      echo "gh: could not resolve to a PR" >&2
      exit 1
    fi
    printf '{"comments":%s}' "$GH_PR_COMMENTS"
    exit 0
  fi
fi

exit 0
GH_STUB_EOF
  chmod +x "$STUB_BIN/gh"

  _ORIGINAL_PATH="$PATH"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  export PATH="$_ORIGINAL_PATH"
  rm -rf "$SANDBOX"
}

# ---------------------------------------------------------------------------
# Scenario: 正常取得 — gh_read_issue_full
# WHEN gh_read_issue_full 499 --repo shuu5/twill を呼び出す
# THEN body テキスト + "## === Comments ===" セパレータ + 全 comments テキストが stdout に返る
# ---------------------------------------------------------------------------

@test "gh_read_issue_full: body テキストが stdout に含まれる" {
  GH_ISSUE_BODY="Issue body text" \
  GH_ISSUE_COMMENTS='[{"body":"First comment"},{"body":"Second comment"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"Issue body text"* ]]
}

@test "gh_read_issue_full: セパレータ '## === Comments ===' が含まれる" {
  run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_issue_full: 全 comments テキストが stdout に含まれる" {
  GH_ISSUE_COMMENTS='[{"body":"First comment"},{"body":"Second comment"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"First comment"* ]]
  [[ "$output" == *"Second comment"* ]]
}

@test "gh_read_issue_full: body がセパレータより前に出力される" {
  GH_ISSUE_BODY="BODY_MARKER" \
  GH_ISSUE_COMMENTS='[{"body":"COMMENT_MARKER"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  # body が separator より前に現れる
  body_pos=$(echo "$output" | grep -n "BODY_MARKER" | head -1 | cut -d: -f1)
  sep_pos=$(echo "$output" | grep -n "## === Comments ===" | head -1 | cut -d: -f1)
  comment_pos=$(echo "$output" | grep -n "COMMENT_MARKER" | head -1 | cut -d: -f1)
  [[ -n "$body_pos" && -n "$sep_pos" && -n "$comment_pos" ]]
  [[ "$body_pos" -lt "$sep_pos" ]]
  [[ "$sep_pos" -lt "$comment_pos" ]]
}

# ---------------------------------------------------------------------------
# Scenario: cross-repo 取得 — --repo フラグが gh CLI に渡される
# WHEN gh_read_issue_full 486 --repo shuu5/twill を cross-repo 環境で呼び出す
# THEN 指定リポジトリの --repo フラグが gh 呼び出しに含まれる
# ---------------------------------------------------------------------------

@test "gh_read_issue_full: --repo フラグが gh 呼び出しに渡される" {
  run bash -c "source '$HELPER_SH' && gh_read_issue_full 486 --repo shuu5/twill"

  assert_success
  grep -q "shuu5/twill" "$GH_CALLS_LOG"
}

@test "gh_read_issue_full: --repo を省略すると現在のリポジトリで実行される" {
  run bash -c "source '$HELPER_SH' && gh_read_issue_full 499"

  assert_success
  # --repo が渡されていないこと（"shuu5/twill" という文字列がログにない）
  ! grep -q "shuu5/twill" "$GH_CALLS_LOG" 2>/dev/null || true
}

@test "gh_read_issue_full[cross-repo]: 指定リポジトリの body が返る" {
  GH_ISSUE_BODY="cross-repo body content" \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 486 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"cross-repo body content"* ]]
}

@test "gh_read_issue_full[cross-repo]: 指定リポジトリの comments が返る" {
  GH_ISSUE_COMMENTS='[{"body":"cross-repo comment"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 486 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"cross-repo comment"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: エラー時フォールバック — gh_read_issue_full
# WHEN 存在しない Issue 番号を指定する（body 取得失敗）
# THEN 空文字列が stdout に返り、stderr に警告メッセージが出力される
# ---------------------------------------------------------------------------

@test "gh_read_issue_full[error]: body 取得失敗時に stdout は空文字列になる" {
  GH_FAIL_BODY=1 \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 99999 --repo shuu5/twill"

  assert_success
  [[ -z "$output" ]]
}

@test "gh_read_issue_full[error]: body 取得失敗時に stderr に警告を出力する" {
  GH_FAIL_BODY=1 \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 99999 --repo shuu5/twill" 2>&1

  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"failed"* ]] || [[ "$output" == *"エラー"* ]]
}

@test "gh_read_issue_full[error]: comments 取得失敗時に stdout は空文字列になる" {
  GH_FAIL_COMMENTS=1 \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 99999 --repo shuu5/twill"

  assert_success
  [[ -z "$output" ]]
}

@test "gh_read_issue_full[error]: comments 取得失敗時に stderr に警告を出力する" {
  GH_FAIL_COMMENTS=1 \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 99999 --repo shuu5/twill" 2>&1

  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"failed"* ]] || [[ "$output" == *"エラー"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: comments が 0 件の場合でも正常動作する（edge case）
# ---------------------------------------------------------------------------

@test "gh_read_issue_full[edge]: comments が空配列でも stdout にセパレータが含まれる" {
  GH_ISSUE_COMMENTS='[]' \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"## === Comments ===" ]] || [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_issue_full[edge]: body が空文字でも stdout にセパレータが含まれる" {
  GH_ISSUE_BODY="" \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"## === Comments ==="* ]]
}

# ---------------------------------------------------------------------------
# Scenario: gh_read_pr_full 正常取得
# WHEN gh_read_pr_full <pr_num> [--repo] を呼び出す
# THEN PR body + "## === Comments ===" + 全 PR comments が stdout に返る
# ---------------------------------------------------------------------------

@test "gh_read_pr_full: PR body が stdout に含まれる" {
  GH_PR_BODY="PR body text" \
  GH_PR_COMMENTS='[{"body":"PR first comment"},{"body":"PR second comment"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"PR body text"* ]]
}

@test "gh_read_pr_full: セパレータ '## === Comments ===' が含まれる" {
  run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_pr_full: 全 PR comments テキストが stdout に含まれる" {
  GH_PR_COMMENTS='[{"body":"PR first comment"},{"body":"PR second comment"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"PR first comment"* ]]
  [[ "$output" == *"PR second comment"* ]]
}

@test "gh_read_pr_full: PR body がセパレータより前に出力される" {
  GH_PR_BODY="PR_BODY_MARKER" \
  GH_PR_COMMENTS='[{"body":"PR_COMMENT_MARKER"}]' \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  body_pos=$(echo "$output" | grep -n "PR_BODY_MARKER" | head -1 | cut -d: -f1)
  sep_pos=$(echo "$output" | grep -n "## === Comments ===" | head -1 | cut -d: -f1)
  comment_pos=$(echo "$output" | grep -n "PR_COMMENT_MARKER" | head -1 | cut -d: -f1)
  [[ -n "$body_pos" && -n "$sep_pos" && -n "$comment_pos" ]]
  [[ "$body_pos" -lt "$sep_pos" ]]
  [[ "$sep_pos" -lt "$comment_pos" ]]
}

# ---------------------------------------------------------------------------
# Scenario: gh_read_pr_full cross-repo
# ---------------------------------------------------------------------------

@test "gh_read_pr_full[cross-repo]: --repo フラグが gh 呼び出しに渡される" {
  run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  grep -q "shuu5/twill" "$GH_CALLS_LOG"
}

@test "gh_read_pr_full[cross-repo]: 指定リポジトリの PR body が返る" {
  GH_PR_BODY="cross-repo PR body" \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"cross-repo PR body"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: gh_read_pr_full エラー時フォールバック
# WHEN 存在しない PR 番号を指定する
# THEN 空文字列が stdout に返り、stderr に警告メッセージが出力される
# ---------------------------------------------------------------------------

@test "gh_read_pr_full[error]: body 取得失敗時に stdout は空文字列になる" {
  GH_FAIL_BODY=1 \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 99999 --repo shuu5/twill"

  assert_success
  [[ -z "$output" ]]
}

@test "gh_read_pr_full[error]: body 取得失敗時に stderr に警告を出力する" {
  GH_FAIL_BODY=1 \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 99999 --repo shuu5/twill" 2>&1

  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"failed"* ]] || [[ "$output" == *"エラー"* ]]
}

@test "gh_read_pr_full[error]: comments 取得失敗時に stdout は空文字列になる" {
  GH_FAIL_COMMENTS=1 \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 99999 --repo shuu5/twill"

  assert_success
  [[ -z "$output" ]]
}

@test "gh_read_pr_full[error]: comments 取得失敗時に stderr に警告を出力する" {
  GH_FAIL_COMMENTS=1 \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 99999 --repo shuu5/twill" 2>&1

  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"failed"* ]] || [[ "$output" == *"エラー"* ]]
}

# ---------------------------------------------------------------------------
# Edge case: gh_read_pr_full — PR comments が 0 件
# ---------------------------------------------------------------------------

@test "gh_read_pr_full[edge]: PR comments が空配列でもセパレータが含まれる" {
  GH_PR_COMMENTS='[]' \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  [[ "$output" == *"## === Comments ==="* ]]
}

# ---------------------------------------------------------------------------
# Edge case: 切り詰めが行われないことの確認
# ---------------------------------------------------------------------------

@test "gh_read_issue_full[no-truncation]: 長い body が切り詰められずに stdout に返る" {
  # 3000文字超の body を生成（一般的な切り詰め閾値を超える）
  local long_body
  long_body="$(printf 'A%.0s' {1..3000})"
  GH_ISSUE_BODY="$long_body" \
    run bash -c "source '$HELPER_SH' && gh_read_issue_full 499 --repo shuu5/twill"

  assert_success
  local actual_len="${#output}"
  [[ "$actual_len" -ge 3000 ]]
}

@test "gh_read_pr_full[no-truncation]: 長い PR body が切り詰められずに stdout に返る" {
  local long_body
  long_body="$(printf 'B%.0s' {1..3000})"
  GH_PR_BODY="$long_body" \
    run bash -c "source '$HELPER_SH' && gh_read_pr_full 42 --repo shuu5/twill"

  assert_success
  local actual_len="${#output}"
  [[ "$actual_len" -ge 3000 ]]
}
