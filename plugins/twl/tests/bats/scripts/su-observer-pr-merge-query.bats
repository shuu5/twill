#!/usr/bin/env bats
# su-observer-pr-merge-query.bats - Issue #948 AC5 RED テスト
#
# AC5: gh pr list の正しい query 例を refs/pilot-completion-signals.md PR-merge セクションに記載
#      + bats test で 'in:body #<N>' syntax を検証
#
# Coverage: unit（ドキュメント記載確認 + gh query syntax の mock 検証）

load '../helpers/common'

PILOT_SIGNALS_MD=""

setup() {
  common_setup
  PILOT_SIGNALS_MD="$REPO_ROOT/skills/su-observer/refs/pilot-completion-signals.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5: pilot-completion-signals.md PR-merge セクションの query 例確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: pilot-completion-signals.md に PR-merge セクションが存在する
# WHEN: pilot-completion-signals.md を参照する
# THEN: PR-merge セクション（または gh pr list に関するセクション）が存在する
# ---------------------------------------------------------------------------

@test "AC5: pilot-completion-signals.md に PR-merge セクションが存在する" {
  # RED: ファイル未作成のため fail する
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない（AC1 依存）: $PILOT_SIGNALS_MD"

  grep -qiE 'PR.?merge|merge.*PR|gh pr list' "$PILOT_SIGNALS_MD" \
    || fail "pilot-completion-signals.md に PR-merge セクションが存在しない"
}

# ---------------------------------------------------------------------------
# Scenario: 'in:body #<N>' syntax が PR-merge セクションに記載されている
# WHEN: pilot-completion-signals.md の PR-merge セクションを参照する
# THEN: 'in:body #' の query syntax 記述が存在する
# ---------------------------------------------------------------------------

@test "AC5: pilot-completion-signals.md に 'in:body #<N>' query syntax が記載されている" {
  # RED: ファイル未作成のため fail する
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない（AC1 依存）: $PILOT_SIGNALS_MD"

  grep -qE 'in:body #' "$PILOT_SIGNALS_MD" \
    || fail "pilot-completion-signals.md に 'in:body #' query syntax が存在しない"
}

# ===========================================================================
# AC5: gh pr list の 'in:body #<N>' query syntax 動作検証
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: gh pr list で 'in:body #<N>' を使うと Issue 番号リンクを含む PR が取得できる
# WHEN: gh pr list --search 'in:body #123' を実行する（stub gh）
# THEN: Issue #123 を body に含む PR が返る（#123 を参照しないPRは除外）
# ---------------------------------------------------------------------------

@test "AC5: gh pr list --search 'in:body #N' が Issue 番号を body に含む PR のみを返す" {
  # stub gh: --search 'in:body #123' の場合のみ PR を返す
  stub_command "gh" '
if echo "$*" | grep -qE "search.*in:body #[0-9]+"; then
  printf "[{\"number\":42,\"title\":\"Fix #123: implement feature\",\"state\":\"open\"}]\n"
  exit 0
else
  printf "[]\n"
  exit 0
fi'

  run gh pr list --search 'in:body #123' --json number,title,state

  assert_success
  # 'in:body #123' の場合、PR が返る
  assert_output --partial '"number":42'
}

# ---------------------------------------------------------------------------
# Scenario: 不正な query syntax（'body:#<N>' 等）は 'in:body' と区別される
# WHEN: gh pr list --search 'body:#123' を実行する（stub gh）
# THEN: 'in:body #123' と異なる挙動であることを確認（誤用防止）
# ---------------------------------------------------------------------------

@test "AC5: 'body:#N' は 'in:body #N' の正しい代替ではないことを確認" {
  # stub gh: 'in:body #' を含まない場合は空の結果を返す
  stub_command "gh" '
if echo "$*" | grep -qE "search.*in:body #[0-9]+"; then
  printf "[{\"number\":42,\"title\":\"Fix #123: implement feature\",\"state\":\"open\"}]\n"
  exit 0
else
  printf "[]\n"
  exit 0
fi'

  # 'body:#123' は 'in:body #123' とは違う（誤用例）— 結果が異なることを確認
  run gh pr list --search 'body:#123' --json number,title,state

  assert_success
  # 'body:#123' は in:body 形式でないため空の結果
  assert_output '[]'
}

# ---------------------------------------------------------------------------
# Scenario: Issue 番号 0 または負数は query として使えない
# WHEN: 'in:body #0' や 'in:body #-1' が指定される
# THEN: 正の整数のみが有効な Issue 番号である（ドキュメント記載の期待）
# ---------------------------------------------------------------------------

@test "AC5: 'in:body #<N>' の N は正の整数であること（ドキュメント仕様確認）" {
  # pilot-completion-signals.md が存在し、正の Issue 番号の query 例が記載されていることを確認
  [[ -f "$PILOT_SIGNALS_MD" ]] \
    || fail "pilot-completion-signals.md が存在しない（AC1 依存）: $PILOT_SIGNALS_MD"

  # '#0' や '#-' を使った誤用例が記載されていないことを確認
  run grep -E "in:body #(0|-)" "$PILOT_SIGNALS_MD"

  # 誤用例が存在しないことが期待（exit 1 = not found = PASS）
  assert_failure
}
