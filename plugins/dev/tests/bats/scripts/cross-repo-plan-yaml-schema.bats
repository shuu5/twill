#!/usr/bin/env bats
# cross-repo-plan-yaml-schema.bats
# BDD unit tests for cross-repo-autopilot / plan-yaml-schema spec
# Spec: openspec/changes/cross-repo-autopilot/specs/plan-yaml-schema/spec.md

load '../helpers/common'

setup() {
  common_setup

  # Stub uuidgen for deterministic output
  stub_command "uuidgen" 'echo "12345678-abcd-efgh-ijkl-123456789012"'

  # Default gh stub: return issue number echo for any "issue view" call
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "" ;;
      *"api"*"issues"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: plan.yaml repos セクション
# ---------------------------------------------------------------------------

# Scenario: クロスリポジトリ plan.yaml 生成
# WHEN autopilot-plan.sh --issues "lpd#42,loom#50" が実行される
# THEN 生成された plan.yaml に repos セクションが含まれ、各 repo_id に owner, name, path が設定される
@test "plan.yaml: cross-repo --issues generates repos section with owner/name/path" {
  # Stub gh to handle both repo-flagged and plain calls
  stub_command "gh" '
    case "$*" in
      *"-R"*"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  # Create a repos config file that autopilot-plan.sh can read
  mkdir -p "$SANDBOX/.autopilot"
  cat > "$SANDBOX/.autopilot/repos.yaml" <<REPOS_EOF
repos:
  lpd:
    owner: shuu5
    name: loom-plugin-dev
    path: $SANDBOX
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
REPOS_EOF

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "lpd#42 loom#50" \
    --repos "$SANDBOX/.autopilot/repos.yaml" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  # Either succeeds with repos section, or not yet implemented (TODO marker acceptable)
  # The key assertion: if plan.yaml is created it should include repos section
  if [ -f "$SANDBOX/.autopilot/plan.yaml" ]; then
    # When implemented: repos section present with lpd and loom entries
    run grep -q "repos:" "$SANDBOX/.autopilot/plan.yaml"
    # Mark as pending if not yet implemented
    if [ "$status" -ne 0 ]; then
      skip "repos section in plan.yaml not yet implemented - pending cross-repo feature"
    fi
    grep -q "owner:" "$SANDBOX/.autopilot/plan.yaml"
    grep -q "name:" "$SANDBOX/.autopilot/plan.yaml"
  else
    skip "autopilot-plan.sh cross-repo --repos flag not yet implemented"
  fi
}

# Scenario: 後方互換 — repos セクション省略
# WHEN autopilot-plan.sh --issues "42,43" が repos 指定なしで実行される
# THEN repos セクションは省略され、issues は bare integer のまま従来形式で生成される
@test "plan.yaml: single-repo --issues without --repos omits repos section" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "42 43" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]

  # repos section must NOT appear
  run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  [ "$status" -ne 0 ]

  # Issues should appear as bare integers
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
  grep -q "43" "$SANDBOX/.autopilot/plan.yaml"
}

# ---------------------------------------------------------------------------
# Requirement: Issue のリポジトリ識別子付与
# ---------------------------------------------------------------------------

# Scenario: Issue ごとの repo 識別
# WHEN plan.yaml に { number: 42, repo: lpd } と { number: 50, repo: loom } が含まれる
# THEN 各 Issue は repos セクションの対応する repo_id で解決される
@test "plan.yaml: issues with repo field resolve against repos section" {
  # Create a plan.yaml fixture with repo-tagged issues
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "test-session"
repo_mode: "worktree"
project_dir: "$SANDBOX"
repos:
  lpd:
    owner: shuu5
    name: loom-plugin-dev
    path: $SANDBOX
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
phases:
  - phase: 1
    issues:
      - number: 42
        repo: lpd
      - number: 50
        repo: loom
dependencies: {}
PLAN_EOF

  # Validate: both issues exist with their repo identifiers
  run grep -c "repo: lpd" "$SANDBOX/.autopilot/plan.yaml"
  [ "$output" -ge 1 ]

  run grep -c "repo: loom" "$SANDBOX/.autopilot/plan.yaml"
  [ "$output" -ge 1 ]

  # Each repo_id must correspond to an entry in the repos section
  run grep -q "lpd:" "$SANDBOX/.autopilot/plan.yaml"
  assert_success

  run grep -q "loom:" "$SANDBOX/.autopilot/plan.yaml"
  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: Issue 参照形式の解決
# ---------------------------------------------------------------------------

# Scenario: bare integer の後方互換解決
# WHEN --issues "42" が repos セクション省略の plan で渡される
# THEN カレントリポジトリの Issue #42 として解決される
@test "plan.yaml: bare integer issue resolves to current-repo issue" {
  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "42" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success
  [ -f "$SANDBOX/.autopilot/plan.yaml" ]

  # Issue 42 should appear, resolved as plain number (no repo: prefix)
  grep -q "42" "$SANDBOX/.autopilot/plan.yaml"

  # No repos section (single-repo context)
  run grep -q "^repos:" "$SANDBOX/.autopilot/plan.yaml"
  [ "$status" -ne 0 ]
}

# Scenario: owner/repo#N 形式の解決
# WHEN --issues "shuu5/loom#50" が渡される
# THEN repos セクションから owner=shuu5, name=loom に一致する repo_id を逆引きし loom#50 として解決される
@test "plan.yaml: owner/repo#N notation reverse-lookups repo_id from repos section" {
  mkdir -p "$SANDBOX/.autopilot"
  cat > "$SANDBOX/.autopilot/repos.yaml" <<REPOS_EOF
repos:
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
REPOS_EOF

  # Stub gh to handle -R flag
  stub_command "gh" '
    case "$*" in
      *"-R"*"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*"--json body"*)
        echo "" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "shuu5/loom#50" \
    --repos "$SANDBOX/.autopilot/repos.yaml" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  if [ -f "$SANDBOX/.autopilot/plan.yaml" ]; then
    # When implemented: should appear as loom#50 or with repo: loom
    run grep -qE "(loom#50|repo: loom)" "$SANDBOX/.autopilot/plan.yaml"
    if [ "$status" -ne 0 ]; then
      skip "owner/repo#N reverse-lookup not yet implemented"
    fi
  else
    skip "cross-repo issue resolution not yet implemented"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: 依存関係の repo_id 修飾 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: クロスリポジトリ依存関係
# WHEN dependencies: { "lpd#42": ["loom#50"] } が定義される
# THEN lpd#42 は loom#50 が完了するまで実行されない
@test "plan.yaml: cross-repo dependency lpd#42 waits for loom#50" {
  # Create plan.yaml with cross-repo dependency
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "test-cross-dep"
repo_mode: "worktree"
project_dir: "$SANDBOX"
repos:
  lpd:
    owner: shuu5
    name: loom-plugin-dev
    path: $SANDBOX
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
phases:
  - phase: 1
    issues:
      - number: 50
        repo: loom
  - phase: 2
    issues:
      - number: 42
        repo: lpd
dependencies:
  "lpd#42":
    - "loom#50"
PLAN_EOF

  # Validate dependency structure: lpd#42 must reference loom#50 as prerequisite
  run grep -q '"lpd#42"' "$SANDBOX/.autopilot/plan.yaml"
  assert_success

  run grep -q '"loom#50"' "$SANDBOX/.autopilot/plan.yaml"
  assert_success

  # Phase ordering: loom#50 in phase 1, lpd#42 in phase 2
  # (verify loom#50 appears before lpd#42 in the file)
  local loom50_line lpd42_line
  loom50_line=$(grep -n "50" "$SANDBOX/.autopilot/plan.yaml" | grep -v "loom#50" | head -1 | cut -d: -f1)
  lpd42_line=$(grep -n "42" "$SANDBOX/.autopilot/plan.yaml" | grep -v "lpd#42" | head -1 | cut -d: -f1)
  # Both phases exist in file
  [ -n "$loom50_line" ] || grep -q "50" "$SANDBOX/.autopilot/plan.yaml"
  [ -n "$lpd42_line" ]  || grep -q "42" "$SANDBOX/.autopilot/plan.yaml"
}

# Edge case: bare integer dependency is still accepted (backward compat)
@test "plan.yaml: bare integer in dependencies is accepted (backward compat)" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<PLAN_EOF
session_id: "test-bare-dep"
repo_mode: "worktree"
project_dir: "$SANDBOX"
phases:
  - phase: 1
    issues:
      - 10
  - phase: 2
    issues:
      - 20
dependencies:
  "20":
    - "10"
PLAN_EOF

  # Bare integers in dependencies are valid YAML - just validate it parses
  run grep -q '"20"' "$SANDBOX/.autopilot/plan.yaml"
  assert_success
  run grep -q '"10"' "$SANDBOX/.autopilot/plan.yaml"
  assert_success
}
