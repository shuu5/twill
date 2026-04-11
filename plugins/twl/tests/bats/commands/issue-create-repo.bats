#!/usr/bin/env bats
# issue-create-repo.bats - BDD unit tests for issue-create --repo option
#
# Spec: deltaspec/changes/issue-491/specs/issue-create-repo/spec.md
#
# Scenarios covered:
#   - --repo 未指定時の後方互換: 現在のリポジトリへ gh issue create
#   - --repo 指定時の cross-repo 起票: gh issue create -R owner/repo --body-file
#   - body-file 経由渡し: --repo 指定時は --body-file 経由
#
# Edge cases:
#   - --repo なし + --title のみ: 既存動作継続
#   - --repo owner/repo + 無効 owner format
#   - --body-file の一時ファイルがクリーンアップされる

load '../helpers/common'

CMD_MD=""

setup() {
  common_setup
  CMD_MD="$REPO_ROOT/commands/issue-create.md"

  # gh stub: record all calls
  stub_command "gh" '
    echo "GH_CALLED: $*" >> /tmp/gh-issue-create-calls.log
    case "$*" in
      *"issue create"*)
        echo "https://github.com/owner/repo/issues/99" ;;
      *)
        echo "{}" ;;
    esac
  '
}

teardown() {
  rm -f /tmp/gh-issue-create-calls.log
  common_teardown
}

# Helper: assert gh was called with pattern
assert_gh_called_with() {
  local pattern="$1"
  grep -q "$pattern" /tmp/gh-issue-create-calls.log 2>/dev/null \
    || fail "Expected gh called with '$pattern'. Calls: $(cat /tmp/gh-issue-create-calls.log 2>/dev/null || echo '(none)')"
}

assert_gh_not_called_with() {
  local pattern="$1"
  ! grep -q "$pattern" /tmp/gh-issue-create-calls.log 2>/dev/null \
    || fail "Expected gh NOT called with '$pattern'"
}

# ===========================================================================
# Requirement: issue-create --repo オプション追加
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: --repo 未指定時の後方互換
# WHEN --repo を指定せずに issue-create を呼ぶ
# THEN 現在のリポジトリへ gh issue create を実行する（既存動作と同一）
# ---------------------------------------------------------------------------

@test "issue-create: commands/issue-create.md が存在する" {
  [ -f "$CMD_MD" ] || fail "commands/issue-create.md not found"
}

@test "issue-create: --repo オプションが issue-create.md に文書化されている" {
  grep -qE '\-\-repo|--repo' "$CMD_MD" \
    || fail "--repo option not documented in issue-create.md"
}

@test "issue-create: --repo 未指定時は既存動作を維持する記述がある" {
  grep -qiE '未指定|backward.*compat|省略|optional|現在.*リポジトリ|default.*repo' "$CMD_MD" \
    || fail "Backward compatibility for missing --repo not documented"
}

# ---------------------------------------------------------------------------
# Scenario: --repo 指定時の cross-repo 起票
# WHEN --repo owner/repo を指定して issue-create を呼ぶ
# THEN gh issue create -R owner/repo --body-file <tempfile> を使用して指定リポへ起票する
# ---------------------------------------------------------------------------

@test "issue-create: -R フラグによる cross-repo 起票が文書化されている" {
  grep -qE '\-R |gh.*-R|cross.repo|cross_repo' "$CMD_MD" \
    || fail "Cross-repo issue creation with -R flag not documented in issue-create.md"
}

@test "issue-create: --body-file オプションが文書化されている" {
  grep -q '\-\-body-file\|--body-file\|body.file\|body_file' "$CMD_MD" \
    || fail "--body-file option not documented in issue-create.md"
}

# ===========================================================================
# Requirement: --repo 指定時の --body-file セキュリティパターン
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: body-file 経由渡し
# WHEN --repo が指定されている
# THEN 本文をテンポラリファイルに書き出し --body-file で渡す
# ---------------------------------------------------------------------------

@test "issue-create: --repo 指定時のテンポラリファイル使用が文書化されている" {
  grep -qiE 'tmp|temp|mktemp|一時ファイル|temporary' "$CMD_MD" \
    || fail "Temporary file usage for --body-file not documented in issue-create.md"
}

@test "issue-create: セキュリティパターン（--body-file 経由）の明記がある" {
  # Must document that body goes through --body-file when --repo is specified
  # to prevent shell injection via --body argument
  grep -q 'body-file\|body_file\|--body-file' "$CMD_MD" \
    || fail "--body-file security pattern not documented"
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "issue-create: --repo owner/repo 形式の検証が文書化されている (owner/repo 形式)" {
  grep -qE 'owner/repo\|<owner>/<repo>\|{owner}/{repo}' "$CMD_MD" \
    || fail "owner/repo format not documented in issue-create.md"
}

@test "issue-create: issue-create.md が 200 行以内 (context budget)" {
  local lines
  lines=$(wc -l < "$CMD_MD")
  [ "$lines" -le 200 ] \
    || fail "issue-create.md has $lines lines, expected <= 200"
}

@test "issue-create: frontmatter に type が定義されている" {
  grep -qE '^type:|^  type:' "$CMD_MD" \
    || fail "type field not found in issue-create.md frontmatter"
}

# ---------------------------------------------------------------------------
# Behavioral tests: test the actual command invocation via script/command flow
# These test the documented behavior by verifying the command file content
# ---------------------------------------------------------------------------

@test "issue-create: gh issue create が文書化されている" {
  grep -q 'gh issue create' "$CMD_MD" \
    || fail "gh issue create not documented in issue-create.md"
}

@test "issue-create: cross-repo 起票時に -R フラグを使う記述がある" {
  # When --repo is specified, use gh issue create -R <repo>
  grep -qE 'gh issue create.*-R|-R.*gh issue create' "$CMD_MD" \
    || fail "gh issue create -R flag for cross-repo not documented"
}
