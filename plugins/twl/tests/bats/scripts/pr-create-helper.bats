#!/usr/bin/env bats
# pr-create-helper.bats - unit tests for scripts/lib/pr-create-helper.sh
#
# Issue #136: PR 本文に Closes #N を機械的に挿入する共通ヘルパー
# Note: bats-support/bats-assert 非依存（環境にサブモジュール未初期化でも実行可能）

setup() {
  REPO_ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  HELPER_SH="$REPO_ROOT_REAL/scripts/lib/pr-create-helper.sh"

  # Create sandbox with throwaway git repo
  SANDBOX="$(mktemp -d)"
  cd "$SANDBOX" || exit 1
  git init -q
  git config user.email t@t
  git config user.name t
  echo a > a.txt
  git add a.txt
  git commit -q -m "feat: initial commit"

  # gh stub: capture all args verbatim
  STUB_BIN="$SANDBOX/.stub-bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
: > "${GH_CAPTURE:-/dev/null}"
for a in "$@"; do
  printf '%s\n' "$a" >> "${GH_CAPTURE:-/dev/null}"
done
echo "https://github.com/o/r/pull/1"
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  export GH_CAPTURE="$SANDBOX/gh-args.txt"
}

teardown() {
  cd /
  rm -rf "$SANDBOX"
}

@test "pr_create_with_closes appends Closes #N when missing from commit body" {
  source "$HELPER_SH"
  pr_create_with_closes 136 quick

  grep -F -- "--body" "$GH_CAPTURE"
  grep -F "Closes #136" "$GH_CAPTURE"
  grep -F -- "--label" "$GH_CAPTURE"
  grep -F "quick" "$GH_CAPTURE"
}

@test "pr_create_with_closes does not duplicate Closes #N when already in commit" {
  echo b > b.txt
  git add b.txt
  git commit -q -m "feat: add b

Closes #99"

  source "$HELPER_SH"
  pr_create_with_closes 99

  local count
  count=$(grep -c "Closes #99" "$GH_CAPTURE" || true)
  [ "$count" -eq 1 ]
}

@test "pr_create_with_closes treats Fixes #N in commit as already-linked" {
  echo c > c.txt
  git add c.txt
  git commit -q -m "fix: bug

Fixes #50"

  source "$HELPER_SH"
  pr_create_with_closes 50

  ! grep -q "Closes #50" "$GH_CAPTURE"
  grep -q "Fixes #50" "$GH_CAPTURE"
}

@test "pr_create_with_closes errors when issue_num is empty" {
  source "$HELPER_SH"
  run pr_create_with_closes ''
  [ "$status" -ne 0 ]
  [[ "$output" == *"ISSUE_NUM 必須"* ]]
}

@test "pr_create_with_closes errors when issue_num is non-numeric" {
  source "$HELPER_SH"
  run pr_create_with_closes 'abc'
  [ "$status" -ne 0 ]
  [[ "$output" == *"不正な ISSUE_NUM"* ]]
}

@test "pr_create_with_closes passes commit subject as title" {
  source "$HELPER_SH"
  pr_create_with_closes 7
  grep -q "feat: initial commit" "$GH_CAPTURE"
}

@test "pr_create_with_closes omits --label when label arg empty" {
  source "$HELPER_SH"
  pr_create_with_closes 8
  ! grep -qx -- "--label" "$GH_CAPTURE"
}
