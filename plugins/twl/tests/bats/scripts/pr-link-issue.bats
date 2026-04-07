#!/usr/bin/env bats
# pr-link-issue.bats - unit tests for scripts/pr-link-issue.sh
#
# Issue #136: 既存 PR 本文に Closes #N を追記する修復ヘルパー
# Note: bats-support/bats-assert 非依存

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SCRIPT_SH="$REPO_ROOT_REAL/scripts/pr-link-issue.sh"

  SANDBOX="$(mktemp -d)"
  STUB_BIN="$SANDBOX/.stub-bin"
  mkdir -p "$STUB_BIN"

  cat > "$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
: > "${GH_CAPTURE:-/dev/null}"
for a in "$@"; do
  printf '%s\n' "$a" >> "${GH_CAPTURE:-/dev/null}"
done

if [[ "$1" == "pr" && "$2" == "view" ]]; then
  cat "${GH_PR_BODY_FILE:-/dev/null}" 2>/dev/null || echo ""
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "edit" ]]; then
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo "${GH_ISSUE_STATE:-OPEN}"
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "close" ]]; then
  echo "closed" > "${GH_ISSUE_CLOSED_MARK:-/dev/null}"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  export GH_CAPTURE="$SANDBOX/gh-args.txt"
  export GH_PR_BODY_FILE="$SANDBOX/pr-body.txt"
  export GH_ISSUE_CLOSED_MARK="$SANDBOX/issue-closed.mark"
}

teardown() {
  rm -rf "$SANDBOX"
}

@test "pr-link-issue appends Closes #N when missing" {
  echo "Original body without close link" > "$GH_PR_BODY_FILE"

  run bash "$SCRIPT_SH" 136 200
  [ "$status" -eq 0 ]
  [[ "$output" == *"追記しました"* ]]

  grep -q "edit" "$GH_CAPTURE"
  grep -q "Closes #136" "$GH_CAPTURE"
}

@test "pr-link-issue is no-op when Closes #N already present" {
  printf 'Body\n\nCloses #136\n' > "$GH_PR_BODY_FILE"

  run bash "$SCRIPT_SH" 136 200
  [ "$status" -eq 0 ]
  [[ "$output" == *"既に Closes #136"* ]]
  ! grep -qx "edit" "$GH_CAPTURE"
}

@test "pr-link-issue treats Fixes #N as already-linked" {
  printf 'Body\n\nFixes #136\n' > "$GH_PR_BODY_FILE"

  run bash "$SCRIPT_SH" 136 200
  [ "$status" -eq 0 ]
  [[ "$output" == *"既に Closes #136"* ]]
  ! grep -qx "edit" "$GH_CAPTURE"
}

@test "pr-link-issue --close-issue calls gh issue close directly" {
  echo "body" > "$GH_PR_BODY_FILE"
  export GH_ISSUE_STATE="OPEN"

  run bash "$SCRIPT_SH" 136 200 --close-issue
  [ "$status" -eq 0 ]
  [ -f "$GH_ISSUE_CLOSED_MARK" ]
  [[ "$output" == *"CLOSED にしました"* ]]
}

@test "pr-link-issue --close-issue is no-op when issue already CLOSED" {
  echo "body" > "$GH_PR_BODY_FILE"
  export GH_ISSUE_STATE="CLOSED"

  run bash "$SCRIPT_SH" 136 200 --close-issue
  [ "$status" -eq 0 ]
  [[ "$output" == *"既に CLOSED"* ]]
  [ ! -f "$GH_ISSUE_CLOSED_MARK" ]
}

@test "pr-link-issue without --close-issue does NOT call gh issue close" {
  echo "body" > "$GH_PR_BODY_FILE"

  run bash "$SCRIPT_SH" 136 200
  [ "$status" -eq 0 ]
  [ ! -f "$GH_ISSUE_CLOSED_MARK" ]
}

@test "pr-link-issue errors when issue_num missing" {
  run bash "$SCRIPT_SH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"必須"* ]]
}

@test "pr-link-issue errors when pr_num missing" {
  run bash "$SCRIPT_SH" 136
  [ "$status" -ne 0 ]
}

@test "pr-link-issue errors on non-numeric issue_num" {
  run bash "$SCRIPT_SH" abc 200
  [ "$status" -ne 0 ]
  [[ "$output" == *"不正な"* ]]
}

@test "pr-link-issue errors on non-numeric pr_num" {
  run bash "$SCRIPT_SH" 136 abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"不正な"* ]]
}

@test "pr-link-issue --help shows usage" {
  run bash "$SCRIPT_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"--close-issue"* ]]
}
