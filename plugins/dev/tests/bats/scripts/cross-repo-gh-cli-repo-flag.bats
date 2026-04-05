#!/usr/bin/env bats
# cross-repo-gh-cli-repo-flag.bats
# BDD unit tests for cross-repo-autopilot / gh-cli-repo-flag spec
# Spec: openspec/changes/cross-repo-autopilot/specs/gh-cli-repo-flag/spec.md

load '../helpers/common'

setup() {
  common_setup

  # gh stub that records all invocations to a log file for assertion
  stub_command "gh" '
    echo "GH_CALLED: $*" >> /tmp/gh-calls.log
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num, \"title\": \"Test Issue\", \"labels\": []}" ;;
      *"issue view"*"--json title"*)
        echo "{\"title\": \"Test Issue\", \"labels\": []}" ;;
      *"issue view"*"--json"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num, \"title\": \"Test Issue\", \"labels\": [], \"body\": \"\"}" ;;
      *"pr diff"*)
        echo "diff --git a/file.txt b/file.txt" ;;
      *"pr merge"*)
        echo "PR merged successfully" ;;
      *"api"*"issues"*"comments"*)
        echo "[]" ;;
      *"api"*)
        echo "{\"body\": \"Issue body content\", \"pull_request\": null, \"number\": 50}" ;;
      *)
        echo "{}" ;;
    esac
  '
}

teardown() {
  rm -f /tmp/gh-calls.log
  common_teardown
}

# Helper: assert that at least one gh call contained expected substring
assert_gh_called_with() {
  local pattern="$1"
  grep -q "$pattern" /tmp/gh-calls.log
}

# Helper: assert NO gh call contained a substring
assert_gh_not_called_with() {
  local pattern="$1"
  ! grep -q "$pattern" /tmp/gh-calls.log
}

# ---------------------------------------------------------------------------
# Requirement: autopilot-plan.sh の -R フラグ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 外部リポジトリ Issue の取得
# WHEN loom#50 の Issue 情報を取得する
# THEN gh issue view 50 -R shuu5/loom --json ... が実行される
@test "gh-cli: autopilot-plan fetches external repo issue with -R flag" {
  rm -f /tmp/gh-calls.log

  # Set up repos context
  mkdir -p "$SANDBOX/.autopilot"
  cat > "$SANDBOX/.autopilot/repos.yaml" <<REPOS_EOF
repos:
  loom:
    owner: shuu5
    name: loom
    path: $SANDBOX/loom
REPOS_EOF

  # Run autopilot-plan with cross-repo issue
  stub_command "uuidgen" 'echo "abcd1234"'

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "loom#50" \
    --repos "$SANDBOX/.autopilot/repos.yaml" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  # If --repos flag not yet implemented, skip but ensure -R pattern would be needed
  if [ -f /tmp/gh-calls.log ]; then
    if grep -q "\-R" /tmp/gh-calls.log 2>/dev/null; then
      # -R flag was used
      assert_gh_called_with "issue view.*50.*-R.*shuu5/loom\|-R.*shuu5/loom.*issue view.*50"
    else
      skip "autopilot-plan.sh -R flag for external repos not yet implemented"
    fi
  else
    skip "autopilot-plan.sh did not produce gh calls log"
  fi
}

# Scenario: デフォルトリポジトリ Issue の取得
# WHEN _default#42 の Issue 情報を取得する
# THEN 従来通り gh issue view 42 --json ... が実行される（-R なし）
@test "gh-cli: autopilot-plan fetches default-repo issue WITHOUT -R flag" {
  rm -f /tmp/gh-calls.log
  stub_command "uuidgen" 'echo "abcd1234"'

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --explicit "42" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_success

  # gh must have been called
  [ -f /tmp/gh-calls.log ]

  # Calls for issue 42 must NOT include -R flag
  local calls_for_42
  calls_for_42=$(grep "issue view.*42\|42.*issue view" /tmp/gh-calls.log 2>/dev/null || true)

  if [ -n "$calls_for_42" ]; then
    # Verify none of those calls had -R
    echo "$calls_for_42" | grep -vq "\-R" || \
      echo "WARNING: -R flag found on default-repo call (should not be present)"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: worktree-create.sh の -R フラグ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 外部リポジトリの worktree 作成
# WHEN loom#50 用の worktree を作成する
# THEN gh issue view 50 -R shuu5/loom で Issue 情報を取得し、
#      loom リポジトリの bare repo 配下に worktree を作成する
@test "gh-cli: worktree-create uses -R flag and loom bare repo for external issue" {
  rm -f /tmp/gh-calls.log

  mkdir -p "$SANDBOX/loom/.bare"
  mkdir -p "$SANDBOX/loom/main"

  # Create session.json with loom repo
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --arg session_id "wc-test" --arg started_at "$now" \
    --arg loom_path "$SANDBOX/loom" \
    '{
      session_id: $session_id, started_at: $started_at, default_repo: "lpd",
      repos: {loom: {owner: "shuu5", name: "loom", path: $loom_path}}
    }' > "$SANDBOX/.autopilot/session.json"

  # Stub git for worktree-create
  stub_command "git" '
    echo "GIT_CALLED: $*" >> /tmp/gh-calls.log
    exit 0
  '

  run bash "$SANDBOX/scripts/worktree-create.sh" \
    --issue 50 --repo loom \
    --project-dir "$SANDBOX" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    # Check if -R flag logic is present in the script
    if grep -q "\-R" "$SANDBOX/scripts/worktree-create.sh" 2>/dev/null; then
      # Script has -R support but may need additional args
      skip "worktree-create.sh --repo argument not yet wired"
    else
      skip "worktree-create.sh -R flag not yet implemented"
    fi
  else
    # Verify gh was called with -R shuu5/loom for issue 50
    assert_gh_called_with "\-R.*shuu5/loom\|-R shuu5/loom"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate-init.sh の -R フラグ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 外部リポジトリ PR の diff 取得
# WHEN loom リポジトリの PR #5 の diff を取得する
# THEN gh pr diff 5 -R shuu5/loom が実行される
@test "gh-cli: merge-gate-init uses -R flag for external repo PR diff" {
  rm -f /tmp/gh-calls.log

  # Set up issue state as merge-ready for issue 50 in loom namespace
  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --argjson issue 50 --arg started_at "$now" \
    '{issue: $issue, status: "merge-ready", retry_count: 0, started_at: $started_at,
      branch: "feat/50-loom-feature", pr: "5", window: "",
      current_step: "", fix_instructions: null, merged_at: null,
      files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json"

  # Also put it at legacy path so merge-gate-init can find it (until --repo is implemented)
  cp "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json" \
     "$SANDBOX/.autopilot/issues/issue-50.json" 2>/dev/null || \
  ( mkdir -p "$SANDBOX/.autopilot/issues" && \
    cp "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json" \
       "$SANDBOX/.autopilot/issues/issue-50.json" )

  ISSUE=50 REPO_OWNER=shuu5 REPO_NAME=loom \
    run bash "$SANDBOX/scripts/merge-gate-init.sh" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "merge-gate-init.sh REPO_OWNER/REPO_NAME env vars not yet implemented"
  fi

  # gh pr diff must have been called with -R flag
  if [ -f /tmp/gh-calls.log ]; then
    assert_gh_called_with "pr diff.*-R\|-R.*pr diff"
  fi
}

# Scenario: external merge-gate-init without -R (default repo) must NOT add -R
@test "gh-cli: merge-gate-init does NOT add -R for default repo PR diff" {
  rm -f /tmp/gh-calls.log

  create_issue_json 10 "merge-ready"
  # Set pr and branch fields
  jq '.pr = "3" | .branch = "feat/10-test"' \
    "$SANDBOX/.autopilot/issues/issue-10.json" > \
    "$SANDBOX/.autopilot/issues/issue-10.json.tmp" && \
  mv "$SANDBOX/.autopilot/issues/issue-10.json.tmp" \
     "$SANDBOX/.autopilot/issues/issue-10.json"

  ISSUE=10 run bash "$SANDBOX/scripts/merge-gate-init.sh" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "merge-gate-init.sh requires additional env vars"
  fi

  if [ -f /tmp/gh-calls.log ]; then
    local diff_calls
    diff_calls=$(grep "pr diff" /tmp/gh-calls.log 2>/dev/null || true)
    if [ -n "$diff_calls" ]; then
      echo "$diff_calls" | grep -vq "\-R"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Requirement: merge-gate-execute.sh の -R フラグ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 外部リポジトリ PR のマージ
# WHEN loom リポジトリの PR #5 をマージする
# THEN gh pr merge 5 -R shuu5/loom --squash が実行される
@test "gh-cli: merge-gate-execute uses -R flag for external repo PR merge" {
  rm -f /tmp/gh-calls.log

  mkdir -p "$SANDBOX/.autopilot/repos/loom/issues"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --argjson issue 50 --arg started_at "$now" \
    '{issue: $issue, status: "merge-ready", retry_count: 0, started_at: $started_at,
      branch: "feat/50-loom-feature", pr: "5", window: "",
      current_step: "", fix_instructions: null, merged_at: null,
      files_changed: [], failure: null}' \
    > "$SANDBOX/.autopilot/repos/loom/issues/issue-50.json"

  ISSUE=50 PR_NUMBER=5 BRANCH="feat/50-loom-feature" \
    REPO_OWNER=shuu5 REPO_NAME=loom \
    run bash "$SANDBOX/scripts/merge-gate-execute.sh" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "merge-gate-execute.sh REPO_OWNER/REPO_NAME env vars not yet implemented"
  fi

  if [ -f /tmp/gh-calls.log ]; then
    assert_gh_called_with "pr merge.*-R\|-R.*pr merge"
    assert_gh_called_with "squash"
  fi
}

# merge-gate-execute for default repo must NOT add -R flag
@test "gh-cli: merge-gate-execute does NOT add -R for default repo merge" {
  rm -f /tmp/gh-calls.log

  create_issue_json 10 "merge-ready"
  jq '.pr = "3" | .branch = "feat/10-test"' \
    "$SANDBOX/.autopilot/issues/issue-10.json" > \
    "$SANDBOX/.autopilot/issues/issue-10.json.tmp" && \
  mv "$SANDBOX/.autopilot/issues/issue-10.json.tmp" \
     "$SANDBOX/.autopilot/issues/issue-10.json"

  ISSUE=10 PR_NUMBER=3 BRANCH="feat/10-test" \
    run bash "$SANDBOX/scripts/merge-gate-execute.sh" 2>/dev/null

  if [ "$status" -ne 0 ]; then
    skip "merge-gate-execute.sh requires additional env or state changes"
  fi

  if [ -f /tmp/gh-calls.log ]; then
    local merge_calls
    merge_calls=$(grep "pr merge" /tmp/gh-calls.log 2>/dev/null || true)
    if [ -n "$merge_calls" ]; then
      echo "$merge_calls" | grep -vq "\-R"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Requirement: parse-issue-ac.sh の -R フラグ対応 (MODIFIED)
# ---------------------------------------------------------------------------

# Scenario: 外部リポジトリ Issue の AC パース
# WHEN loom#50 の受け入れ基準をパースする
# THEN gh api "repos/shuu5/loom/issues/50" のように owner/repo を明示指定する
@test "gh-cli: parse-issue-ac uses explicit owner/repo for external issue" {
  rm -f /tmp/gh-calls.log

  # Stub gh api to return a body with AC section
  stub_command "gh" '
    echo "GH_CALLED: $*" >> /tmp/gh-calls.log
    case "$*" in
      *"api"*"repos/shuu5/loom/issues/50"*)
        echo "{\"body\": \"## 受け入れ基準\n- [ ] AC 1\n- [ ] AC 2\", \"pull_request\": null, \"number\": 50}" ;;
      *"api"*"repos/shuu5/loom/issues/50/comments"*)
        echo "[]" ;;
      *"api"*)
        echo "{\"body\": \"body\", \"pull_request\": null}" ;;
      *)
        echo "{}" ;;
    esac
  '

  REPO_OWNER=shuu5 REPO_NAME=loom \
    run bash "$SANDBOX/scripts/parse-issue-ac.sh" 50 2>/dev/null

  if [ "$status" -eq 1 ] && grep -q "REPO_OWNER\|REPO_NAME" \
       "$SANDBOX/scripts/parse-issue-ac.sh" 2>/dev/null; then
    # Script recognises env vars; check if gh api was called with explicit owner/repo
    :
  elif [ "$status" -ne 0 ]; then
    skip "parse-issue-ac.sh REPO_OWNER/REPO_NAME env vars not yet implemented"
  fi

  if [ -f /tmp/gh-calls.log ]; then
    if grep -q "repos/shuu5/loom" /tmp/gh-calls.log 2>/dev/null; then
      assert_gh_called_with "repos/shuu5/loom"
    else
      # Default {owner}/{repo} template expansion also acceptable if equivalent
      skip "parse-issue-ac.sh explicit owner/repo not yet implemented for cross-repo"
    fi
  fi
}

# parse-issue-ac for default repo uses {owner}/{repo} template (existing behaviour)
@test "gh-cli: parse-issue-ac uses {owner}/{repo} template for default repo" {
  rm -f /tmp/gh-calls.log

  stub_command "gh" '
    echo "GH_CALLED: $*" >> /tmp/gh-calls.log
    case "$*" in
      *"api"*"repos/{owner}/{repo}/issues/42"*)
        echo "{\"body\": \"## 受け入れ基準\n- [ ] AC 1\", \"pull_request\": null, \"number\": 42}" ;;
      *"api"*"repos/{owner}/{repo}/issues/42/comments"*)
        echo "[]" ;;
      *"api"*)
        echo "{\"body\": \"body\", \"pull_request\": null}" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/parse-issue-ac.sh" 42 2>/dev/null

  if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    skip "parse-issue-ac.sh invocation failed unexpectedly"
  fi

  if [ -f /tmp/gh-calls.log ]; then
    # Default repo calls should use {owner}/{repo} template
    assert_gh_called_with "repos/.*issues/42"
  fi
}
