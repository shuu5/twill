#!/usr/bin/env bats
# gh-read-content.bats - unit tests for scripts/lib/gh-read-content.sh
#
# Issue #499: gh-read-content ヘルパー新設
# Spec: deltaspec/changes/issue-499/specs/gh-read-content/spec.md
# Note: bats-support/bats-assert 非依存（環境にサブモジュール未初期化でも実行可能）
#
# Tested functions:
#   gh_read_issue_full <issue_num> [--repo <owner/repo>]
#   gh_read_pr_full <pr_num> [--repo <owner/repo>]

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  HELPER_SH="$REPO_ROOT_REAL/scripts/lib/gh-read-content.sh"

  SANDBOX="$(mktemp -d)"
  GH_CALLS_LOG="$SANDBOX/gh-calls.log"
  export GH_CALLS_LOG

  STUB_BIN="$SANDBOX/.stub-bin"
  mkdir -p "$STUB_BIN"

  # シンプルな gh スタブ: Python 非依存
  # GH_FAIL_BODY=1        → body 取得で exit 1
  # GH_FAIL_COMMENTS=1    → comments 取得で exit 1
  # GH_ISSUE_BODY         → issue body の出力内容
  # GH_ISSUE_COMMENTS_OUT → issue comments の出力内容（既に結合済み文字列）
  # GH_PR_BODY            → PR body の出力内容
  # GH_PR_COMMENTS_OUT    → PR comments の出力内容
  cat > "$STUB_BIN/gh" <<'GH_STUB_EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_CALLS_LOG:-/dev/null}"

subcmd="$1"; shift   # issue or pr
subsubcmd="$1"; shift # view

[[ "$subsubcmd" != "view" ]] && exit 0

# Scan for --json flag
json_field=""
has_repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) json_field="$2"; shift 2 ;;
    -q|--jq) shift 2 ;;
    --repo) has_repo="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ "$subcmd" == "issue" ]]; then
  if [[ "$json_field" == "body" ]]; then
    [[ -n "${GH_FAIL_BODY:-}" ]] && exit 1
    printf '%s\n' "${GH_ISSUE_BODY:-Issue body text}"
  elif [[ "$json_field" == "comments" ]]; then
    [[ -n "${GH_FAIL_COMMENTS:-}" ]] && exit 1
    printf '%s\n' "${GH_ISSUE_COMMENTS_OUT:-First comment

---

Second comment}"
  fi
elif [[ "$subcmd" == "pr" ]]; then
  if [[ "$json_field" == "body" ]]; then
    [[ -n "${GH_FAIL_BODY:-}" ]] && exit 1
    printf '%s\n' "${GH_PR_BODY:-PR body text}"
  elif [[ "$json_field" == "comments" ]]; then
    [[ -n "${GH_FAIL_COMMENTS:-}" ]] && exit 1
    printf '%s\n' "${GH_PR_COMMENTS_OUT:-PR comment one

---

PR comment two}"
  fi
fi
GH_STUB_EOF
  chmod +x "$STUB_BIN/gh"

  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$SANDBOX"
}

# ---------------------------------------------------------------------------
# gh_read_issue_full: 正常取得
# ---------------------------------------------------------------------------

@test "gh_read_issue_full: body テキストが stdout に含まれる" {
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  [[ "$output" == *"Issue body text"* ]]
}

@test "gh_read_issue_full: セパレータ が含まれる" {
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_issue_full: 全 comments テキストが stdout に含まれる" {
  export GH_ISSUE_COMMENTS_OUT="First comment

---

Second comment"
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  [[ "$output" == *"First comment"* ]]
  [[ "$output" == *"Second comment"* ]]
}

@test "gh_read_issue_full: body がセパレータより前に出力される" {
  export GH_ISSUE_BODY="BODY_MARKER_XYZ"
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  body_pos=$(echo "$output" | grep -n "BODY_MARKER_XYZ" | head -1 | cut -d: -f1)
  sep_pos=$(echo "$output" | grep -n "## === Comments ===" | head -1 | cut -d: -f1)
  [ -n "$body_pos" ]
  [ -n "$sep_pos" ]
  [ "$body_pos" -lt "$sep_pos" ]
}

# ---------------------------------------------------------------------------
# gh_read_issue_full: cross-repo
# ---------------------------------------------------------------------------

@test "gh_read_issue_full: --repo フラグが gh 呼び出しに渡される" {
  source "$HELPER_SH"
  run gh_read_issue_full 486 --repo shuu5/twill
  [ "$status" -eq 0 ]
  grep -q "shuu5/twill" "$GH_CALLS_LOG"
}

@test "gh_read_issue_full: --repo を省略すると repo フラグなし" {
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  ! grep -q -- "--repo" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# gh_read_issue_full: エラー時フォールバック
# ---------------------------------------------------------------------------

@test "gh_read_issue_full[error]: body/comments 取得失敗時に status は 0" {
  export GH_FAIL_BODY=1
  export GH_FAIL_COMMENTS=1
  source "$HELPER_SH"
  run gh_read_issue_full 999
  [ "$status" -eq 0 ]
}

@test "gh_read_issue_full[error]: body/comments 取得失敗時に stdout は空文字列" {
  export GH_FAIL_BODY=1
  export GH_FAIL_COMMENTS=1
  source "$HELPER_SH"
  result=$(gh_read_issue_full 999 2>/dev/null)
  [ -z "$result" ]
}

@test "gh_read_issue_full[error]: issue 番号未指定時に status は 0" {
  source "$HELPER_SH"
  run gh_read_issue_full ""
  [ "$status" -eq 0 ]
}

@test "gh_read_issue_full[error]: issue 番号未指定時に stdout は空文字列" {
  source "$HELPER_SH"
  result=$(gh_read_issue_full "" 2>/dev/null)
  [ -z "$result" ]
}

# ---------------------------------------------------------------------------
# gh_read_issue_full: edge cases
# ---------------------------------------------------------------------------

@test "gh_read_issue_full[edge]: comments が空でもセパレータが含まれる" {
  export GH_ISSUE_COMMENTS_OUT=""
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_issue_full[edge]: 長い body を切り詰めない" {
  long_body="$(python3 -c "print('X' * 3000)")"
  export GH_ISSUE_BODY="$long_body"
  source "$HELPER_SH"
  run gh_read_issue_full 499
  [ "$status" -eq 0 ]
  [ "${#output}" -ge 3000 ]
}

# ---------------------------------------------------------------------------
# gh_read_pr_full: 正常取得
# ---------------------------------------------------------------------------

@test "gh_read_pr_full: PR body が stdout に含まれる" {
  source "$HELPER_SH"
  run gh_read_pr_full 392
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR body text"* ]]
}

@test "gh_read_pr_full: セパレータ が含まれる" {
  source "$HELPER_SH"
  run gh_read_pr_full 392
  [ "$status" -eq 0 ]
  [[ "$output" == *"## === Comments ==="* ]]
}

@test "gh_read_pr_full: 全 PR comments が stdout に含まれる" {
  export GH_PR_COMMENTS_OUT="PR comment one

---

PR comment two"
  source "$HELPER_SH"
  run gh_read_pr_full 392
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR comment one"* ]]
  [[ "$output" == *"PR comment two"* ]]
}

@test "gh_read_pr_full: PR body がセパレータより前に出力される" {
  export GH_PR_BODY="PR_BODY_MARKER_XYZ"
  source "$HELPER_SH"
  run gh_read_pr_full 392
  [ "$status" -eq 0 ]
  body_pos=$(echo "$output" | grep -n "PR_BODY_MARKER_XYZ" | head -1 | cut -d: -f1)
  sep_pos=$(echo "$output" | grep -n "## === Comments ===" | head -1 | cut -d: -f1)
  [ -n "$body_pos" ]
  [ -n "$sep_pos" ]
  [ "$body_pos" -lt "$sep_pos" ]
}

# ---------------------------------------------------------------------------
# gh_read_pr_full: cross-repo
# ---------------------------------------------------------------------------

@test "gh_read_pr_full: --repo フラグが gh 呼び出しに渡される" {
  source "$HELPER_SH"
  run gh_read_pr_full 392 --repo shuu5/twill
  [ "$status" -eq 0 ]
  grep -q "shuu5/twill" "$GH_CALLS_LOG"
}

# ---------------------------------------------------------------------------
# gh_read_pr_full: エラー時フォールバック
# ---------------------------------------------------------------------------

@test "gh_read_pr_full[error]: body 取得失敗時に status は 0" {
  export GH_FAIL_BODY=1
  export GH_FAIL_COMMENTS=1
  source "$HELPER_SH"
  run gh_read_pr_full 999
  [ "$status" -eq 0 ]
}

@test "gh_read_pr_full[error]: body 取得失敗時に stdout は空文字列" {
  export GH_FAIL_BODY=1
  export GH_FAIL_COMMENTS=1
  source "$HELPER_SH"
  result=$(gh_read_pr_full 999 2>/dev/null)
  [ -z "$result" ]
}

@test "gh_read_pr_full[edge]: 長い PR body を切り詰めない" {
  long_body="$(python3 -c "print('Y' * 3000)")"
  export GH_PR_BODY="$long_body"
  source "$HELPER_SH"
  run gh_read_pr_full 392
  [ "$status" -eq 0 ]
  [ "${#output}" -ge 3000 ]
}
