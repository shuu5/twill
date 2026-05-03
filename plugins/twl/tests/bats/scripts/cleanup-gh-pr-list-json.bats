#!/usr/bin/env bats
# cleanup-gh-pr-list-json.bats
# Issue #1351: autopilot-cleanup.sh の gh pr list を --json number --jq 'length' 方式に置換
#
# AC 検証:
#   AC1: gh pr list の呼び出しに --json number --jq 'length' が含まれる
#   AC2: PR 数の判定が _open_pr_count -gt 0 (数値比較) になっている
#   AC3: gh 失敗時は || echo '0' でフォールバックし tr -cd '0-9' でサニタイズ
#   AC4: オープン PR が 1 件以上なら worktree を保持するセマンティクスを維持
#   AC5: 静的検査 (bash -n) が通る
#
# RED phase: AC1-AC4 は実装前 (旧 gh pr list --state open 形式) では FAIL する

load '../helpers/common'

setup() {
  common_setup

  # worktree-delete.sh stub: 常に成功（AC4 behavioral test 用）
  cat > "$SANDBOX/scripts/worktree-delete.sh" << 'WDEOF'
#!/usr/bin/env bash
exit 0
WDEOF
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC1: gh pr list の呼び出しに --json number と --jq 'length' が含まれる
# RED: 現在は --state open のみで --json number / --jq フラグなし
# ---------------------------------------------------------------------------

@test "ac1[cleanup-gh-pr-list-json]: gh pr list を --json number 形式で呼び出している" {
  run grep -q -- '--json number' "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

@test "ac1[cleanup-gh-pr-list-json]: gh pr list コマンドに --jq オプションが含まれる" {
  run grep -q -- '--jq' "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# AC2: PR 数の判定が _open_pr_count 変数を使った数値比較になっている
# RED: 現在は _open_prs 変数 + [[ -n ... ]] の文字列空判定
# ---------------------------------------------------------------------------

@test "ac2[cleanup-gh-pr-list-json]: _open_pr_count 変数が実装されている" {
  run grep -q '_open_pr_count' "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

@test "ac2[cleanup-gh-pr-list-json]: PR 件数判定が _open_pr_count -gt 0 (数値比較) を使用している" {
  run grep -qE '_open_pr_count[[:space:]]+-gt[[:space:]]+0' "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# AC3: gh 失敗時は || echo '0' でフォールバックし tr -cd '0-9' でサニタイズ
# RED: 現在は || true (空文字列フォールバック) で tr サニタイズなし
# ---------------------------------------------------------------------------

@test "ac3[cleanup-gh-pr-list-json]: gh 失敗時に || echo '0' でフォールバックしている" {
  run grep -q "|| echo '0'" "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

@test "ac3[cleanup-gh-pr-list-json]: tr -cd '0-9' で数値以外を除去している" {
  run grep -q "tr -cd '0-9'" "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}

# ---------------------------------------------------------------------------
# AC4: OPEN PR が 1 件以上なら git push --delete をスキップするセマンティクスを維持
#
# RED mechanism:
#   gh stub は --json と --jq 両方のフラグが存在する場合のみ "1" を返す。
#   旧実装は --json/--jq なしで gh を呼ぶため stub は "" を返す。
#   "" は数値比較用変数が未設定/空のため [[ -n "$_open_prs" ]] が false となり
#   git push --delete が実行される → テスト FAIL (RED)。
#   新実装は --json number --jq 'length' で呼ぶため stub が "1" を返す。
#   1 -gt 0 が true → git push --delete はスキップされる → テスト PASS (GREEN)。
# ---------------------------------------------------------------------------

@test "ac4[cleanup-gh-pr-list-json]: gh pr list が 1 を返す場合 git push --delete をスキップ" {
  GIT_PUSH_LOG="$SANDBOX/git_push.log"

  # git stub: worktree list --porcelain で孤立 worktree を返し、push --delete はログに記録
  cat > "$STUB_BIN/git" << GITEOF
#!/usr/bin/env bash
case "\$*" in
  *"worktree list"*)
    printf 'worktree %s/main\nHEAD 0000000000000000000000000000000000000000\nbranch refs/heads/main\n\n' "$SANDBOX"
    printf 'worktree %s/worktrees/feat-1351-orphan\nHEAD 1111111111111111111111111111111111111111\nbranch refs/heads/feat/1351-orphan\n\n' "$SANDBOX"
    ;;
  *"push"*"--delete"*)
    echo "git \$*" >> "$GIT_PUSH_LOG"
    ;;
esac
exit 0
GITEOF
  chmod +x "$STUB_BIN/git"

  # gh stub: --json と --jq 両方のフラグが存在する場合のみ "1" を返す（新 API 形式）
  # 旧形式（--state open のみ）は "" を返す → 旧実装では push --delete が走る
  cat > "$STUB_BIN/gh" << 'GHEOF'
#!/usr/bin/env bash
if echo "$*" | grep -q -- '--json' && echo "$*" | grep -q -- '--jq'; then
  echo "1"
else
  echo ""
fi
GHEOF
  chmod +x "$STUB_BIN/gh"

  # issues/ を空にして feat/1351-orphan が孤立状態になるようにする
  rm -f "$SANDBOX/.autopilot/issues"/*.json 2>/dev/null || true

  run bash "$SANDBOX/scripts/autopilot-cleanup.sh" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_success

  # git push --delete が呼ばれていないこと（OPEN PR があるためスキップされるべき）
  run test -f "$GIT_PUSH_LOG"
  assert_failure
}

# ---------------------------------------------------------------------------
# AC5: 静的検査 (bash -n) が通る
# GREEN: 文法エラーがなければ実装前から PASS。実装後の回帰防止テスト
# ---------------------------------------------------------------------------

@test "ac5[cleanup-gh-pr-list-json]: bash -n による静的構文チェックが通る" {
  run bash -n "$SANDBOX/scripts/autopilot-cleanup.sh"
  assert_success
}
