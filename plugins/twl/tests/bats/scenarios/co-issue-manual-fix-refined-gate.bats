#!/usr/bin/env bats
# co-issue-manual-fix-refined-gate.bats — TDD RED phase tests for Issue #988
#
# 検証対象: co-issue manual fix [B] path dual-write (ADR-024)
#   - SKILL.md L301-305 に --add-label refined + board-status-update Refined の両 step が存在すること
#   - MUST NOT セクションに Phase 4 manual fix の不変条件が追加されていること
#   - issue-mgmt.md に manual fix [B] path dual-write 義務の記述があること
#   - mock gh + fake chain-runner.sh を使った call sequence 検証
#
# RED フェーズ: 実装前は全テストが FAIL する。
#   - AC1: SKILL.md に dual-write コマンド行が 2 行以上 → 現時点 0 行
#   - AC2: SKILL.md に Phase 4 manual fix 不変条件 → 現時点存在しない
#   - AC3(i): call sequence test で add-label + board-status-update 両呼び出し確認 → スクリプト未存在
#   - AC3(ii): add-label が board-status-update より先に呼ばれること → スクリプト未存在
#   - AC6: issue-mgmt.md に manual fix 記述 → 現時点 0 件

setup() {
  # BATS_TEST_DIRNAME = .../plugins/twl/tests/bats/scenarios
  # worktree root は 5 段上
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  SKILL_MD_PATH="$REPO_ROOT/plugins/twl/skills/co-issue/SKILL.md"
  ISSUE_MGMT_MD_PATH="$REPO_ROOT/plugins/twl/architecture/domain/contexts/issue-mgmt.md"
  MANUAL_FIX_B_SCRIPT="$REPO_ROOT/plugins/twl/scripts/co-issue-manual-fix-b.sh"

  TEST_TMP="$(mktemp -d)"
  CALLS_LOG="$TEST_TMP/calls.log"
  MOCK_BIN_DIR="$TEST_TMP/bin"
  mkdir -p "$MOCK_BIN_DIR"

  # fake gh: すべての呼び出しを calls.log に記録して exit 0
  cat > "$MOCK_BIN_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$CALLS_LOG"
exit 0
MOCK_EOF
  chmod +x "$MOCK_BIN_DIR/gh"

  # fake chain-runner.sh: すべての呼び出しを calls.log に記録して exit 0
  cat > "$MOCK_BIN_DIR/chain-runner.sh" <<MOCK_EOF
#!/usr/bin/env bash
echo "chain-runner.sh \$*" >> "$CALLS_LOG"
exit 0
MOCK_EOF
  chmod +x "$MOCK_BIN_DIR/chain-runner.sh"

  export CALLS_LOG
  export PATH="$MOCK_BIN_DIR:$PATH"
  export SCRIPTS_ROOT="$MOCK_BIN_DIR"
  export ISSUE_NUMBER="999"
  export ISSUE_REPO="shuu5/twill"

  touch "$CALLS_LOG"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# AC1: SKILL.md L301-305 に dual-write コマンドが 2 行以上存在すること
# RED: 現時点では SKILL.md に --add-label refined / board-status-update Refined が存在しないため FAIL
# ---------------------------------------------------------------------------
@test "ac1(a): SKILL.md contains --add-label refined command" {
  # AC: SKILL.md の manual fix [B] path に gh issue edit --add-label refined の step が存在する
  # RED: 実装前は grep が 0 件マッチ → FAIL
  run grep -E -- '--add-label refined' "$SKILL_MD_PATH"
  [ "$status" -eq 0 ]
}

@test "ac1(b): SKILL.md contains board-status-update Refined command" {
  # AC: SKILL.md の manual fix [B] path に chain-runner.sh board-status-update Refined の step が存在する
  # RED: 実装前は grep が 0 件マッチ → FAIL
  run grep -E 'board-status-update.*Refined' "$SKILL_MD_PATH"
  [ "$status" -eq 0 ]
}

@test "ac1(c): SKILL.md dual-write commands total count >= 2" {
  # AC: --add-label refined と board-status-update Refined の合計が 2 以上
  # RED: 実装前は 0 件 → FAIL
  local count
  count=$(grep -cE '(--add-label refined|board-status-update.*Refined)' "$SKILL_MD_PATH" || true)
  [ "$count" -ge 2 ]
}

# ---------------------------------------------------------------------------
# AC2: SKILL.md の禁止事項セクションに Phase 4 manual fix 不変条件が追加されていること
# RED: 現時点では存在しないため FAIL
# ---------------------------------------------------------------------------
@test "ac2: SKILL.md MUST NOT section contains Phase 4 manual fix invariant" {
  # AC: 禁止事項セクションに「Phase 4 manual fix [B] path 完遂前に refined label + Status=Refined 遷移を skip してはならない」
  # RED: 実装前は存在しない → FAIL
  run grep -q 'Phase 4 manual fix' "$SKILL_MD_PATH"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3(i): call sequence test — add-label refined と board-status-update Refined の両呼び出しが存在すること
# mock 戦略: PATH override で fake gh および fake chain-runner.sh を inject
# RED: co-issue-manual-fix-b.sh が存在しないため FAIL
# ---------------------------------------------------------------------------
@test "ac3-state: manual-fix-b script calls both add-label refined and board-status-update Refined" {
  # AC: co-issue-manual-fix-b.sh 実行後、calls.log に両コマンド行が存在すること
  # RED: スクリプトが存在しないため command_not_found で FAIL
  run bash "$MANUAL_FIX_B_SCRIPT" "$ISSUE_NUMBER" "$ISSUE_REPO"
  [ "$status" -eq 0 ]

  # add-label refined の呼び出しが calls.log に存在すること
  run grep -F -- '--add-label refined' "$CALLS_LOG"
  [ "$status" -eq 0 ]

  # board-status-update Refined の呼び出しが calls.log に存在すること
  run grep -E 'board-status-update.*Refined' "$CALLS_LOG"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC3(ii): call sequence verify — add-label refined が board-status-update Refined より先に呼ばれること
# RED: スクリプトが存在しないため FAIL
# ---------------------------------------------------------------------------
@test "ac3-sequence: add-label refined is called before board-status-update Refined" {
  # AC: calls.log で --add-label refined の行番号 < board-status-update Refined の行番号
  # RED: スクリプトが存在しないため command_not_found で FAIL
  run bash "$MANUAL_FIX_B_SCRIPT" "$ISSUE_NUMBER" "$ISSUE_REPO"
  [ "$status" -eq 0 ]

  # add-label refined の行番号を取得
  local add_label_line board_status_line
  add_label_line=$(grep -n -- '--add-label refined' "$CALLS_LOG" | head -1 | cut -d: -f1)
  board_status_line=$(grep -n 'board-status-update.*Refined' "$CALLS_LOG" | head -1 | cut -d: -f1)

  # 両行が存在すること
  [ -n "$add_label_line" ]
  [ -n "$board_status_line" ]

  # add-label の行番号が board-status-update より小さいこと (label 先行)
  [ "$add_label_line" -lt "$board_status_line" ]
}

# ---------------------------------------------------------------------------
# AC6: issue-mgmt.md に manual fix [B] path の dual-write 義務記述があること
# RED: 現時点では 0 件 → FAIL
# ---------------------------------------------------------------------------
@test "ac6: issue-mgmt.md contains manual fix [B] path dual-write obligation" {
  # AC: issue-mgmt.md に「co-issue manual fix [B] path も dual-write 義務 MUST」の記述がある
  # RED: 実装前は存在しない → FAIL
  run grep -q 'manual fix' "$ISSUE_MGMT_MD_PATH"
  [ "$status" -eq 0 ]
}
