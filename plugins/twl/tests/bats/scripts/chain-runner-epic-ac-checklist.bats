#!/usr/bin/env bats
# chain-runner-epic-ac-checklist.bats
# Requirement: Issue #1070 — 子 Issue が "Done" に遷移した時、子 body の
#              `Closes-AC: #EPIC:ACN` 全行について 親 Epic body の
#              `- [ ] **AC{N}**` を `- [x]` に flip する。
# Spec: ADR-024 dual-write 規約「AC checklist auto-update」
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

# python3 stub: update-epic-ac-checklist と resolve-project をモック化
# 他 (state read/write 等) は実体に委譲
# Args: $1=ac_update_exit_code (0=flipped / 2=no-op / 1=error)
_setup_python_stub_full() {
  local ac_update_exit_code="${1:-0}"

  cat > "$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"twl.autopilot.github update-epic-ac-checklist"*)
    exit ${ac_update_exit_code}
    ;;
  *"twl.autopilot.github extract-parent-epic"*)
    # AC1+AC2 (#1026) hook が同じ step で発火するので minimal stub。
    # parent なし扱い → AC1+AC2 hook はスキップ → AC3 hook のみテストできる
    exit 2
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

# gh stub: project list / item-add / field-list / item-edit を mock
# bats 側は AC checklist update の "Python helper が呼ばれた回数" のみで判定するため、
# AC checklist 更新の gh issue edit は Python stub 内で完結 (gh は呼ばれない)
_setup_gh_stub() {
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
    echo '{"items":[]}'
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

# Capture python3 invocations (subset). $PY_LOG records what was called.
_setup_python_stub_capture() {
  local ac_update_exit_code="${1:-0}"
  PY_LOG="$SANDBOX/python-calls.log"
  export PY_LOG
  : > "$PY_LOG"

  cat > "$STUB_BIN/python3" <<EOF
#!/usr/bin/env bash
echo "py: \$*" >> "$PY_LOG"
case "\$*" in
  *"twl.autopilot.github update-epic-ac-checklist"*)
    exit ${ac_update_exit_code}
    ;;
  *"twl.autopilot.github extract-parent-epic"*)
    exit 2
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

# ===========================================================================
# AC1: target_status="Done" + Closes-AC ある + flip 成功 → Python helper 呼ばれる
# ===========================================================================

@test "epic-ac-checklist[done-flip]: target_status='Done' で update-epic-ac-checklist が呼ばれ ok ログ" {
  _setup_python_stub_capture 0
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "Done"

  assert_success
  # Python helper が呼ばれたことを確認
  local py_count
  py_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$py_count" -ge 1 ]] || {
    echo "FAIL: update-epic-ac-checklist が呼ばれていない (py_count=$py_count)" >&2
    cat "$PY_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC2: target_status="Done" + Closes-AC なし → Python helper 呼ばれるが no-op (exit 2)
# ===========================================================================

@test "epic-ac-checklist[no-closes-ac]: Closes-AC なし (exit 2) で skip ログ + step は success" {
  _setup_python_stub_capture 2
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "Done"

  assert_success
  # Python helper は呼ばれる (gating は Python 側)
  local py_count
  py_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$py_count" -ge 1 ]] || {
    echo "FAIL: update-epic-ac-checklist が呼ばれていない" >&2
    return 1
  }
}

# ===========================================================================
# AC3: target_status="In Progress" → AC checklist hook はスキップ (target guard)
# ===========================================================================

@test "epic-ac-checklist[target-guard-in-progress]: target_status='In Progress' では AC checklist hook が起動しない" {
  _setup_python_stub_capture 0
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  # AC checklist hook は呼ばれてはならない
  local py_count
  py_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$py_count" -eq 0 ]] || {
    echo "FAIL: target_status='In Progress' なのに update-epic-ac-checklist が呼ばれた (count=$py_count)" >&2
    cat "$PY_LOG" >&2
    return 1
  }
}

# ===========================================================================
# AC4: target_status="Refined" でも AC checklist hook はスキップ
# ===========================================================================

@test "epic-ac-checklist[target-guard-refined]: target_status='Refined' でも AC checklist hook が起動しない" {
  _setup_python_stub_capture 0
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "Refined"

  assert_success
  local py_count
  py_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$py_count" -eq 0 ]] || {
    echo "FAIL: target_status='Refined' で AC checklist hook が起動した" >&2
    return 1
  }
}

# ===========================================================================
# AC5: Python helper が exit 1 (失敗) → step は success (suppress strategy)
# ===========================================================================

@test "epic-ac-checklist[suppress-failure]: Python helper exit 1 でも step は success (skip ログ)" {
  _setup_python_stub_capture 1
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "Done"

  # 失敗を suppress するため step は成功扱い
  assert_success
  # Python helper は呼ばれた
  local py_count
  py_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$py_count" -ge 1 ]] || {
    echo "FAIL: update-epic-ac-checklist が呼ばれていない" >&2
    return 1
  }
}

# ===========================================================================
# AC6: AC1+AC2 hook (parent-epic-transition) と AC3 hook (epic-ac-checklist) は
# 直交する — target_status="In Progress" では AC1+AC2 のみ起動
# ===========================================================================

@test "epic-ac-checklist[orthogonal]: 'In Progress' で AC1+AC2 hook が起動するが AC3 hook は起動しない" {
  _setup_python_stub_capture 0
  _setup_gh_stub

  run bash "$CR" board-status-update 9001 "In Progress"

  assert_success
  # AC1+AC2 (extract-parent-epic) は呼ばれる
  local parent_count
  parent_count=$(grep -c "extract-parent-epic" "$PY_LOG" || true)
  [[ "$parent_count" -ge 1 ]] || {
    echo "FAIL: target_status='In Progress' で extract-parent-epic が呼ばれていない" >&2
    cat "$PY_LOG" >&2
    return 1
  }
  # AC3 (update-epic-ac-checklist) は呼ばれない
  local ac_count
  ac_count=$(grep -c "update-epic-ac-checklist" "$PY_LOG" || true)
  [[ "$ac_count" -eq 0 ]] || {
    echo "FAIL: target_status='In Progress' で update-epic-ac-checklist が呼ばれた" >&2
    return 1
  }
}
