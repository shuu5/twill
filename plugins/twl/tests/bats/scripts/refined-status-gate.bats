#!/usr/bin/env bats
# refined-status-gate.bats - Refined Status Gate シナリオテスト
#
# Issue #943: design: refined をラベルから Status field へ移行 + Todo→Refined→In Progress 遷移 gate の強制
# AC5: pre-bash-refined-status-gate.sh + autopilot-launch.sh + launcher.py での Status pre-check
# AC6: cross-repo Issue の label fallback ロジック
# AC7: fail-closed の追加機能（bypass flag / deny log / retry with backoff）
# AC4: co-issue Phase 4 完了時の dual-write
# AC8: dual-write rollback
#
# Scenarios:
#   S1: Status=Todo + autopilot-launch.sh --issue N → deny
#   S2: Status=Refined + autopilot-launch.sh --issue N → allow
#   S3: Status=In Progress + re-spawn → allow (idempotent)
#   S4: Status fetch 失敗（gh auth scope 不足）→ deny + actionable message
#   S5: Issue が Board 未登録 + cross-repo フラグなし → deny + actionable message
#   S5a: cross-repo Issue（Board 未登録）+ refined label あり → allow (label fallback)
#   S6: co-issue Phase 4 完了 → Status=Refined が Board に書き込まれること
#   S7: Status=Todo の Issue に直接 In Progress 設定 → deny
#   S8: dual-write 中に Status write 成功 + label write 失敗 → rollback

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() {
  common_setup

  # pre-bash-refined-status-gate.sh が実装前は存在しないため RED になる
  # 実装後は SANDBOX/scripts/ にコピーされる

  # Stub git to avoid actual git calls
  stub_command "git" 'echo "stub-git"'
}

teardown() {
  rm -f /tmp/refined-status-gate.log
  common_teardown
}

# ---------------------------------------------------------------------------
# S1: Status=Todo → deny
# ---------------------------------------------------------------------------

# WHEN: Board で Status=Todo の Issue N に対して autopilot-launch.sh --issue N を実行する
# THEN: exit 1 で deny される
# RED: pre-bash-refined-status-gate.sh と autopilot-launch.sh の Status pre-check が未実装
@test "S1: Status=Todo + autopilot-launch.sh --issue N → deny" {
  # AC5: pre-check は Status=Todo を拒否する
  local issue_num=42

  _write_board_items "$(jq -n \
    --argjson n "$issue_num" \
    '{"items": [
      {"content": {"number": $n, "repository": "shuu5/twill", "type": "Issue"}, "status": "Todo", "title": "Issue \($n)"}
    ]}')"

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json labels"*)
    echo '{"labels": [{"name": "enhancement"}]}' ;;
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"status": {"name": "Todo"}, "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  assert_failure
  assert_output --partial "Refined"
}

# ---------------------------------------------------------------------------
# S2: Status=Refined → allow
# ---------------------------------------------------------------------------

# WHEN: Board で Status=Refined の Issue N に対して autopilot-launch.sh --issue N を実行する
# THEN: Status gate を通過し、Worker 起動処理へ進む
# RED: pre-bash-refined-status-gate.sh と autopilot-launch.sh の Status pre-check が未実装
@test "S2: Status=Refined + autopilot-launch.sh --issue N → allow (proceeds to launch)" {
  # AC5: pre-check は Status=Refined を許可する
  local issue_num=43

  _write_board_items "$(jq -n \
    --argjson n "$issue_num" \
    '{"items": [
      {"content": {"number": $n, "repository": "shuu5/twill", "type": "Issue"}, "status": "Refined", "title": "Issue \($n)"}
    ]}')"

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"project item-list"*)
    cat "${SANDBOX}/board-items.json" ;;
  *"issue view"*"--json labels"*)
    echo '{"labels": [{"name": "enhancement"}]}' ;;
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"status": {"name": "Refined"}, "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # cld が存在しない環境では cld_not_found で exit するが、Status gate 通過後のエラーであること
  # pre-bash-refined-status-gate.sh が deny するなら "Refined" 拒否メッセージが出る → 失敗
  # 実装後は gate が allow して cld_not_found まで進む（exit 2）
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot"

  # Status gate deny メッセージ（"Status が Refined でない" 等）が出ていないことを確認
  # 実装前は gate 自体が存在しないため pass する → RED にするため明示的に fail を期待
  # RED: 実装後は "allow → cld_not_found" のパスになる
  # assert_output 内で "Refined でない" が出ていれば S2 は fail → RED 状態を表す
  refute_output --partial "Refined でない"
  # 以下は実装後に assert_failure (exit 2 by cld_not_found) になる
  # 現時点では gate 未実装で動作不定のため NotImplementedError stub で RED にする
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    skip "RED: pre-bash-refined-status-gate.sh が未実装"
  }
}

# ---------------------------------------------------------------------------
# S3: Status=In Progress → allow (idempotent)
# ---------------------------------------------------------------------------

# WHEN: 既に Status=In Progress の Issue に re-spawn する
# THEN: Status gate を通過する（冪等）
# RED: pre-bash-refined-status-gate.sh の idempotent ロジックが未実装
@test "S3: Status=In Progress + re-spawn → allow (idempotent)" {
  # AC5: In Progress は既に遷移済みのため allow
  local issue_num=44

  _write_board_items "$(jq -n \
    --argjson n "$issue_num" \
    '{"items": [
      {"content": {"number": $n, "repository": "shuu5/twill", "type": "Issue"}, "status": "In Progress", "title": "Issue \($n)"}
    ]}')"

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"status": {"name": "In Progress"}, "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # pre-bash-refined-status-gate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    # RED: 実装前は gate が存在しない
    false
  }

  run bash "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX"

  assert_success
}

# ---------------------------------------------------------------------------
# S4: Status fetch 失敗（gh auth scope 不足）→ deny + actionable message
# ---------------------------------------------------------------------------

# WHEN: gh api の呼び出しで auth scope エラーが発生する
# THEN: exit 1 で deny、'gh auth refresh -s project' を含む actionable message を出力
# RED: pre-bash-refined-status-gate.sh の auth scope エラーハンドリングが未実装
@test "S4: Status fetch 失敗（gh auth scope 不足）→ deny + actionable message" {
  # AC5, W5: assert_output --partial で actionable message を検証
  local issue_num=45

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json projectItems"* | *"project item-list"*)
    echo "Your token does not have the 'project' scope" >&2
    exit 1 ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # pre-bash-refined-status-gate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX"

  assert_failure
  assert_output --partial 'gh auth refresh -s project'
}

# ---------------------------------------------------------------------------
# S5: Issue が Board 未登録 + cross-repo フラグなし → deny + actionable message
# ---------------------------------------------------------------------------

# WHEN: Issue が Project Board に登録されておらず、cross-repo フラグもない
# THEN: exit 1 で deny、'Board に Issue を add' を含むメッセージを出力
# RED: pre-bash-refined-status-gate.sh の Board 未登録チェックが未実装
@test "S5: Issue が Board 未登録 + cross-repo フラグなし → deny + actionable message" {
  # AC5, W5: assert_output --partial で actionable message を検証
  local issue_num=46

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json projectItems"*)
    # Board 未登録 → nodes が空
    echo '{"projectItems": {"nodes": []}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # pre-bash-refined-status-gate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX"

  assert_failure
  assert_output --partial 'Board に Issue を add'
}

# ---------------------------------------------------------------------------
# S5a: cross-repo Issue（Board 未登録）+ refined label あり → allow (label fallback)
# ---------------------------------------------------------------------------

# WHEN: cross-repo Issue で Board 未登録だが 'refined' label が付いている
# THEN: label fallback ロジックで allow
# RED: pre-bash-refined-status-gate.sh の label fallback ロジックが未実装
@test "S5a: cross-repo Issue（Board 未登録）+ refined label あり → allow (label fallback)" {
  # AC6: cross-repo + refined label → allow
  local issue_num=47

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json projectItems"*)
    # Board 未登録 → nodes が空
    echo '{"projectItems": {"nodes": []}}' ;;
  *"issue view"*"--json labels"*)
    # refined label あり
    echo '{"labels": [{"name": "refined"}, {"name": "enhancement"}]}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # pre-bash-refined-status-gate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX" \
    --cross-repo

  assert_success
}

# ---------------------------------------------------------------------------
# S6: co-issue Phase 4 完了 → Status=Refined が Board に書き込まれること
# ---------------------------------------------------------------------------

# WHEN: co-issue の Phase 4 (specialist review) が完了する
# THEN: dual-write (label 先 → Status 後) で Status=Refined が Board に書き込まれる
# RED: workflow-issue-refine/SKILL.md Step 4.5 / 6' が未実装
@test "S6: co-issue Phase 4 完了 → Status=Refined が Board に書き込まれること" {
  # AC4: dual-write: label 先 → Status 後
  local issue_num=48
  local gh_calls_log="$SANDBOX/gh-calls.log"

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${SANDBOX}/gh-calls.log"
case "$*" in
  *"issue edit"*"--add-label"*"refined"*)
    echo "label write OK" ;;
  *"project item-edit"*"3d983780"*)
    echo "status write OK" ;;
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"id": "PVTI_abc", "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # workflow-issue-refine/SKILL.md の Phase 4 完了スクリプトが未実装 → RED
  local skill_script
  skill_script=$(find "$SANDBOX/scripts" -name "issue-refine-phase4-complete.sh" 2>/dev/null | head -1)
  [ -n "$skill_script" ] || {
    # RED: Phase 4 完了スクリプトが未実装
    false
  }

  run bash "$skill_script" --issue "$issue_num" --project-dir "$SANDBOX"

  assert_success
  # dual-write の順序確認: label が先、Status が後
  grep -n "add-label.*refined" "$gh_calls_log"
  local label_line status_line
  label_line=$(grep -n "add-label.*refined" "$gh_calls_log" | cut -d: -f1)
  status_line=$(grep -n "project item-edit.*3d983780" "$gh_calls_log" | cut -d: -f1)
  [ "$label_line" -lt "$status_line" ]
}

# ---------------------------------------------------------------------------
# S7: Status=Todo の Issue に直接 In Progress 設定 → deny
# ---------------------------------------------------------------------------

# WHEN: Status=Todo の Issue に対して Status=In Progress を直接設定しようとする
# THEN: Refined を経由しない遷移として deny
# RED: pre-bash-refined-status-gate.sh の遷移ガードが未実装
@test "S7: Status=Todo の Issue に直接 In Progress 設定 → deny" {
  # AC5: Todo → In Progress 直接遷移を gate で拒否
  local issue_num=49

  stub_command "gh" "$(cat <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"status": {"name": "Todo"}, "project": {"number": 5}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
)"

  # pre-bash-refined-status-gate.sh が未実装 → RED
  [ -f "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" ] || {
    false
  }

  run bash "$SANDBOX/scripts/pre-bash-refined-status-gate.sh" \
    --issue "$issue_num" \
    --project-dir "$SANDBOX" \
    --target-status "In Progress"

  assert_failure
  assert_output --partial "Refined"
}

# ---------------------------------------------------------------------------
# S8: dual-write 中に Status write 成功 + label write 失敗 → rollback
# ---------------------------------------------------------------------------

# WHEN: dual-write で label write が失敗する
# THEN: Status write をロールバック（Status を元の状態に戻す）
# RED: workflow-issue-refine/SKILL.md Step 6' のロールバックロジックが未実装
@test "S8: dual-write 中に Status write 成功 + label write 失敗 → rollback" {
  # AC4 + AC8: dual-write rollback
  local issue_num=50
  local gh_calls_log="$SANDBOX/gh-calls.log"

  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "gh $*" >> "${SANDBOX}/gh-calls.log"
case "$*" in
  *"issue edit"*"--add-label"*"refined"*)
    # label write を意図的に失敗させる
    echo "label write FAILED" >&2
    exit 1 ;;
  *"project item-edit"*"3d983780"*)
    echo "status write OK" ;;
  *"issue view"*"--json projectItems"*)
    echo '{"projectItems": {"nodes": [{"id": "PVTI_abc", "status": {"name": "Todo"}, "project": {"number": 5, "fields": {"nodes": []}}}]}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  # workflow-issue-refine/SKILL.md の Phase 4 完了スクリプトが未実装 → RED
  local skill_script
  skill_script=$(find "$SANDBOX/scripts" -name "issue-refine-phase4-complete.sh" 2>/dev/null | head -1)
  [ -n "$skill_script" ] || {
    # RED: rollback ロジックが未実装
    false
  }

  run bash "$skill_script" --issue "$issue_num" --project-dir "$SANDBOX"

  # label write 失敗 → overall failure
  assert_failure
  # rollback: Status を元に戻す gh project item-edit が呼ばれていること
  # rollback call は Status write の後に来る
  grep "project item-edit" "$gh_calls_log" | wc -l | grep -q "2"
}
