#!/usr/bin/env bats
# autopilot-plan-board-detect.bats - Project 検出 + クロスリポジトリ + 後方互換
#
# Spec: openspec/changes/110-autopilot-board-mode/specs/board-mode.md
# Scenarios: Project検出(1/複数/なし), クロスリポジトリ, 単一リポ, 後方互換

load '../helpers/common'
load './autopilot-plan-board-helpers'

setup() { common_setup; }
teardown() { common_teardown; }

# ---------------------------------------------------------------------------
# Requirement: クロスリポジトリ Issue 自動解決
# ---------------------------------------------------------------------------

@test "autopilot-plan --board auto-builds --repos JSON for cross-repo board items" {
  stub_command "uuidgen" 'echo "test-uuid-cross-0001"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
  *"project list"*)
    echo '{"projects": [{"number": 5, "title": "loom-plugin-dev board"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_abc", "title": "loom-plugin-dev board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"content": {"number": 110, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo",        "title": "Issue 110"},
      {"content": {"number": 56,  "repository": "shuu5/loom",            "type": "Issue"}, "status": "In Progress", "title": "Issue 56"}
    ]}' ;;
  *"issue view"*"--json number"*)
    num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
    echo "{\"number\": $num}" ;;
  *"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"api"*"comments"*)
    echo "[]" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "loom" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "110" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "56" "$SANDBOX/.autopilot/plan.yaml"
}

@test "autopilot-plan --board does not build --repos for single-repo board" {
  _write_board_items '{"items": [
    {"content": {"number": 42, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo",        "title": "Issue 42"},
    {"content": {"number": 43, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "In Progress", "title": "Issue 43"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  assert_failure
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "43" "$SANDBOX/.autopilot/plan.yaml"
}

# ---------------------------------------------------------------------------
# Requirement: Project Board 自動検出
# ---------------------------------------------------------------------------

@test "autopilot-plan --board detects single linked project and fetches items" {
  _write_board_items '{"items": [
    {"content": {"number": 42, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo", "title": "Issue 42"}
  ]}'
  _stub_gh_single_project

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
}

@test "autopilot-plan --board prefers project whose title contains repo name when multiple projects exist" {
  stub_command "uuidgen" 'echo "test-uuid-multi-0001"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
  *"project list"*)
    echo '{"projects": [
      {"number": 5, "title": "generic board"},
      {"number": 7, "title": "loom-plugin-dev tasks"}
    ]}' ;;
  *"api graphql"*"-F num=5"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_005", "title": "generic board", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"api graphql"*"-F num=7"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_007", "title": "loom-plugin-dev tasks", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_000", "title": "unknown", "repositories": {"nodes": []}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"content": {"number": 77, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo", "title": "Issue 77"}
    ]}' ;;
  *"issue view"*"--json number"*)
    num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
    echo "{\"number\": $num}" ;;
  *"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"api"*"comments"*)
    echo "[]" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  grep -q "77" "$SANDBOX/.autopilot/plan.yaml"
}

@test "autopilot-plan --board falls back to first matching project when no title match" {
  stub_command "uuidgen" 'echo "test-uuid-multi-0002"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
  *"project list"*)
    echo '{"projects": [
      {"number": 3, "title": "alpha project"},
      {"number": 4, "title": "beta project"}
    ]}' ;;
  *"api graphql"*"-F num=3"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_003", "title": "alpha project", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"api graphql"*"-F num=4"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_004", "title": "beta project", "repositories": {"nodes": [{"nameWithOwner": "shuu5/loom-plugin-dev"}]}}}}}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_000", "title": "unknown", "repositories": {"nodes": []}}}}}' ;;
  *"project item-list"*)
    echo '{"items": [
      {"content": {"number": 55, "repository": "shuu5/loom-plugin-dev", "type": "Issue"}, "status": "Todo", "title": "Issue 55"}
    ]}' ;;
  *"issue view"*"--json number"*)
    num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
    echo "{\"number\": $num}" ;;
  *"issue view"*"--json body"*)
    echo "No dependencies" ;;
  *"api"*"comments"*)
    echo "[]" ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  grep -q "55" "$SANDBOX/.autopilot/plan.yaml"
}

@test "autopilot-plan --board exits 1 when no project is linked to repository" {
  stub_command "uuidgen" 'echo "test-uuid-noproject-0001"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
  *"project list"*)
    echo '{"projects": [{"number": 9, "title": "unrelated project"}]}' ;;
  *"api graphql"*)
    echo '{"data": {"user": {"projectV2": {"id": "PVT_009", "title": "unrelated project", "repositories": {"nodes": []}}}}}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
  assert_output --partial "Error: リポジトリにリンクされた Project Board が見つかりません"
}

@test "autopilot-plan --board exits 1 when project list is empty" {
  stub_command "uuidgen" 'echo "test-uuid-noproject-0002"'
  cat > "$STUB_BIN/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"--json nameWithOwner"*)
    echo '{"nameWithOwner": "shuu5/loom-plugin-dev"}' ;;
  *"project list"*)
    echo '{"projects": []}' ;;
  *)
    echo "{}" ;;
esac
GHSTUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --board --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_failure
}

# ---------------------------------------------------------------------------
# 後方互換性
# ---------------------------------------------------------------------------

@test "autopilot-plan --explicit still works after --board mode is added" {
  stub_command "uuidgen" 'echo "test-uuid-compat-0001"'
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *) echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "10 → 11" --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  assert_output --partial "Phases: 2"
}

@test "autopilot-plan --issues still works after --board mode is added" {
  stub_command "uuidgen" 'echo "test-uuid-compat-0002"'
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "No dependencies" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *) echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "20 21" --project-dir "$SANDBOX" --repo-mode "worktree"

  assert_success
  assert_output --partial "plan.yaml 生成完了"
  assert_output --partial "Phases: 1"
}
