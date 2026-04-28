#!/usr/bin/env bats
# chain-runner-parent-epic-transition.bats
# Requirement: Issue #1026 ADR-024 AC1+AC2 — 子 Issue が "In Progress" に遷移した時、
#              親 Epic が "Refined" なら "In Progress" に自動遷移する
# Spec: ADR-024 dual-write 規約「子 Issue 実装着手で親 Epic 自動 In Progress 遷移」
# Coverage: --type=integration --coverage=autopilot

load '../helpers/common'

setup() {
  common_setup

  CR="$SANDBOX/scripts/chain-runner.sh"
  export CR

  GH_LOG="$SANDBOX/gh-calls.log"
  export GH_LOG
  : > "$GH_LOG"

  PYTHON_REAL=$(command -v python3)
  export PYTHON_REAL
}

teardown() {
  common_teardown
}

# python3 stub: extract-parent-epic と resolve-project をモック化
# 他 (state read/write 等) は実体に委譲
# Args: $1=parent_num (空文字列で extract-parent-epic exit 2)
_setup_python_stub_full() {
  local parent_num="${1:-}"

  cat > "$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"twl.autopilot.github extract-parent-epic"*)
    if [[ -z "$parent_num" ]]; then
      exit 2
    fi
    echo "$parent_num"
    exit 0
    ;;
  *"twl.autopilot.github resolve-project"*)
    cat <<'JSON'
{"project_num":"99","project_id":"PVT_mock_proj","owner":"shuu5","repo_name":"twill","repo_fullname":"shuu5/twill"}
JSON
    exit 0
    ;;
  *)
    exec "$PYTHON_REAL" "\$@"
    ;;
esac
EOF
  chmod +x "$STUB_BIN/python3"
}

# gh stub: project list / item-add / field-list / item-list / item-edit / issue view を mock
# Args: $1=parent_status ("Refined", "In Progress", "Done")
_setup_gh_stub() {
  local parent_status="${1:-Refined}"

  cat > "$STUB_BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh: \$*" >> "$GH_LOG"
case "\$*" in
  "project list --owner @me --limit 1")
    echo '[]'
    exit 0
    ;;
  "project item-add"*)
    echo '{"id":"PVTI_mock_item_id"}'
    exit 0
    ;;
  "project field-list"*)
    cat <<'JSON'
{
  "fields": [
    {
      "name": "Status",
      "id": "PVTSSF_mock_status_field",
      "options": [
        {"name":"Refined","id":"opt_refined"},
        {"name":"In Progress","id":"opt_in_progress"},
        {"name":"Done","id":"opt_done"}
      ]
    }
  ]
}
JSON
    exit 0
    ;;
  "project item-list"*)
    # M3 (Quality Review follow-up): 実 API を反映し複数 items を返す。
    # parent (#100) 以外に other Issue (#9001)、PR (#500)、Draft、別 Issue (#200) を含める。
    # jq filter が type=Issue + number=100 で正しく親 Epic のみ選別することを検証。
    cat <<JSON_EOF
{
  "items": [
    {
      "id": "PVTI_other_issue",
      "content": {"number": 9001, "type": "Issue"},
      "status": "In Progress"
    },
    {
      "id": "PVTI_some_pr",
      "content": {"number": 500, "type": "PullRequest"},
      "status": "In Progress"
    },
    {
      "id": "PVTI_draft_item",
      "content": {"type": "DraftIssue"},
      "status": "Backlog"
    },
    {
      "id": "PVTI_mock_item_id",
      "content": {"number": 100, "type": "Issue"},
      "status": "${parent_status}"
    },
    {
      "id": "PVTI_unrelated_issue",
      "content": {"number": 200, "type": "Issue"},
      "status": "Done"
    }
  ]
}
JSON_EOF
    exit 0
    ;;
  "issue view"*)
    echo '{"body":"some body","number":1}'
    exit 0
    ;;
  "project item-edit"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
}

# ===========================================================================
# AC1: 親 Epic Refined → In Progress 遷移
# ===========================================================================

@test "parent-epic-transition[RED]: 親 Epic が Refined の場合、In Progress に遷移する" {
  _setup_python_stub_full "100"
  _setup_gh_stub "Refined"

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  # 子 Issue 用 1 回 + 親 Epic 用 1 回 = 計 2 回の item-edit
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || true)
  [[ "$edit_count" -ge 2 ]] || {
    echo "FAIL: 親 Epic Refined→In Progress の item-edit が呼ばれていない (edit_count=$edit_count)" >&2
    cat "$GH_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC2: 親 Epic 既に In Progress → idempotent
# ===========================================================================

@test "parent-epic-transition[idempotent]: 親 Epic が In Progress なら item-edit が呼ばれない (idempotent)" {
  _setup_python_stub_full "100"
  _setup_gh_stub "In Progress"

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || true)
  [[ "$edit_count" -eq 1 ]] || {
    echo "FAIL: 親 Epic In Progress なのに item-edit が ${edit_count} 回呼ばれた (期待: 1 = 子のみ)" >&2
    cat "$GH_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC3 (regression): 親 Epic Done → 何もしない
# ===========================================================================

@test "parent-epic-transition[regression-done]: 親 Epic が Done なら item-edit が呼ばれない" {
  _setup_python_stub_full "100"
  _setup_gh_stub "Done"

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || true)
  [[ "$edit_count" -eq 1 ]] || {
    echo "FAIL: 親 Epic Done なのに item-edit が ${edit_count} 回呼ばれた (期待: 1)" >&2
    cat "$GH_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC4: 子 Issue に Parent 行なし → hook 全体スキップ
# ===========================================================================

@test "parent-epic-transition[no-parent]: 子 Issue に Parent 行がない場合、親 Epic hook はスキップ" {
  _setup_python_stub_full ""  # extract-parent-epic exit 2
  _setup_gh_stub "Refined"

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || true)
  [[ "$edit_count" -eq 1 ]] || {
    echo "FAIL: Parent なしなのに親 Epic 用 item-edit が呼ばれた (edit_count=${edit_count})" >&2
    cat "$GH_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC5: target_status != "In Progress" → hook スキップ
# ===========================================================================

@test "parent-epic-transition[target-guard]: target_status='Done' では親 Epic hook がスキップされる" {
  _setup_python_stub_full "100"
  _setup_gh_stub "Refined"

  run bash "$CR" board-status-update 9001 "Done"

  assert_success
  local edit_count
  edit_count=$(grep -c "project item-edit" "$GH_LOG" || true)
  [[ "$edit_count" -eq 1 ]] || {
    echo "FAIL: target_status='Done' なのに親 Epic hook が動作した (edit_count=${edit_count})" >&2
    cat "$GH_LOG" >&2
    return 1
  }
}
