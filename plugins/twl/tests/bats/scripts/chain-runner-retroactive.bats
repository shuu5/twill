#!/usr/bin/env bats
# chain-runner-retroactive.bats
# Unit tests for Issue #397: Retroactive DeltaSpec mode detection in chain-runner.sh
#
# Spec: deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md
#
# Coverage:
#   Requirement: Retroactive DeltaSpec モード検出
#     1. git diff origin/main...HEAD が DeltaSpec ファイルのみ → deltaspec_mode=retroactive
#     2. git diff に *.py / *.sh / *.ts が含まれる → deltaspec_mode 未設定（通常モード）
#
#   Requirement: Implementation PR の追跡
#     3. Issue body に "Implemented-in: #<N>" タグあり → implementation_pr=<N> が state に保存
#     4. Issue body に タグなし → stdout/stderr に implementation_pr 入力プロンプト
#
#   Requirement: Cross-PR AC 検証
#     5. issue-<N>.json に implementation_pr: 392 → gh pr view 392 --json mergeCommit が呼ばれる
#     6. implementation_pr が未設定 → 通常の PR diff に対して AC チェック（cross-PR 呼出しなし）
#
#   Requirement: workflow-setup init の retroactive 対応
#     7. retroactive モード検出 → init の JSON 出力に recommended_action: retroactive_propose
#
# NOTE: Tests tagged [PENDING] will fail until the feature is implemented in
#       chain-runner.sh / chain.py. They document the expected contract.

load '../helpers/common'

setup() {
  common_setup

  # Stub git: branch = feat/397-retroactive, project root = $SANDBOX
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *"diff"*"--name-only"*)
        # Default: DeltaSpec-only diff
        printf "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n"
        printf "deltaspec/changes/issue-397/proposal.md\n" ;;
      *)
        exit 0 ;;
    esac
  '

  # Stub gh: issue view returns body with Implemented-in tag by default
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json body"*)
        echo "{\"body\": \"Retroactive DeltaSpec\n\nImplemented-in: #392\n\"}" ;;
      *"pr view"*"--json mergeCommit"*)
        echo "{\"mergeCommit\":{\"oid\":\"abc123def456\"}}" ;;
      *)
        exit 0 ;;
    esac
  '

  # Create a minimal issue-397.json
  mkdir -p "$SANDBOX/.autopilot/issues"
  jq -n '{
    issue: 397,
    status: "running",
    branch: "feat/397-retroactive",
    pr: null,
    window: "",
    started_at: "2026-04-10T00:00:00Z",
    current_step: "init",
    retry_count: 0,
    fix_instructions: null,
    merged_at: null,
    files_changed: [],
    failure: null
  }' > "$SANDBOX/.autopilot/issues/issue-397.json"

  # Create minimal deltaspec structure (no impl files)
  mkdir -p "$SANDBOX/deltaspec/changes/issue-397/specs/retroactive-deltaspec"
  echo "## Spec" > "$SANDBOX/deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: Retroactive DeltaSpec モード検出
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 実装コードなし・ドキュメントのみの差分 [PENDING]
# WHEN: git diff origin/main...HEAD が DeltaSpec ファイルのみを含む
# THEN: issue-<N>.json の deltaspec_mode が retroactive に設定される
# ---------------------------------------------------------------------------

@test "[PENDING] init: DeltaSpec-only diff → deltaspec_mode=retroactive in state file" {
  # Override git stub to return DeltaSpec-only diff
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n"
        printf "deltaspec/changes/issue-397/proposal.md\n" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  # The state file must contain deltaspec_mode=retroactive
  local mode
  mode="$(jq -r '.deltaspec_mode // empty' "$SANDBOX/.autopilot/issues/issue-397.json")"
  [ "$mode" = "retroactive" ]
}

@test "[PENDING] init: DeltaSpec-only diff → recommended_action is retroactive_propose" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  # The JSON output must contain recommended_action=retroactive_propose
  local action
  action="$(echo "$output" | jq -r '.recommended_action // empty' 2>/dev/null)"
  [ "$action" = "retroactive_propose" ]
}

# ---------------------------------------------------------------------------
# Scenario: 実装コードが含まれる通常ケース
# WHEN: git diff に *.py / *.sh / *.ts 等が含まれる
# THEN: deltaspec_mode は設定されない（通常モード）
# ---------------------------------------------------------------------------

@test "[PENDING] init: diff with impl files → deltaspec_mode NOT set to retroactive" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/397-mixed" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/spec.md\n"
        printf "plugins/twl/scripts/chain-runner.sh\n"
        printf "cli/twl/src/twl/autopilot/chain.py\n" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  local mode
  mode="$(jq -r '.deltaspec_mode // empty' "$SANDBOX/.autopilot/issues/issue-397.json")"
  [ "$mode" != "retroactive" ]
}

@test "[PENDING] init: diff with impl files → recommended_action is NOT retroactive_propose" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "feat/397-mixed" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/spec.md\n"
        printf "cli/twl/src/twl/autopilot/chain.py\n" ;;
      *)
        exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  local action
  action="$(echo "$output" | jq -r '.recommended_action // empty' 2>/dev/null)"
  [ "$action" != "retroactive_propose" ]
}

# ===========================================================================
# Requirement: Implementation PR の追跡
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Issue body からの自動検出 [PENDING]
# WHEN: Issue body に `Implemented-in: #<N>` タグが存在する
# THEN: implementation_pr が自動的に <N> に設定される
# ---------------------------------------------------------------------------

@test "[PENDING] init: Implemented-in tag in Issue body → implementation_pr saved to state" {
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json body"*)
        echo "{\"body\": \"Retroactive DeltaSpec\n\nImplemented-in: #392\n\"}" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/spec.md\n" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  local impl_pr
  impl_pr="$(jq -r '.implementation_pr // empty' "$SANDBOX/.autopilot/issues/issue-397.json")"
  [ "$impl_pr" = "392" ]
}

# ---------------------------------------------------------------------------
# Scenario: 自動検出できない場合の手動入力 [PENDING]
# WHEN: Issue body に Implemented-in タグが存在しない
# THEN: ユーザーに implementation_pr の入力を求めるプロンプトが表示される
# ---------------------------------------------------------------------------

@test "[PENDING] init: no Implemented-in tag → stdout/stderr includes implementation_pr prompt" {
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json body"*)
        echo "{\"body\": \"No tag here.\"}" ;;
      *)
        exit 0 ;;
    esac
  '
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/spec.md\n" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  # The combined output must mention implementation_pr for the user to act on
  echo "$output" | grep -qi "implementation_pr"
}

# ===========================================================================
# Requirement: Cross-PR AC 検証
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: implementation_pr が設定されている場合の AC 検証 [PENDING]
# WHEN: issue-<N>.json に implementation_pr: 392 が設定されている
# THEN: gh pr view 392 --json mergeCommit でコミット SHA を取得し AC チェック
# ---------------------------------------------------------------------------

@test "[PENDING] ac-verify: implementation_pr=392 in state → gh pr view 392 --json mergeCommit called" {
  # Set implementation_pr in state file
  jq '. + {"implementation_pr": 392}' \
    "$SANDBOX/.autopilot/issues/issue-397.json" \
    > "$SANDBOX/.autopilot/issues/issue-397.json.tmp"
  mv "$SANDBOX/.autopilot/issues/issue-397.json.tmp" \
     "$SANDBOX/.autopilot/issues/issue-397.json"

  # Record gh invocations to a file
  local gh_log="$SANDBOX/gh_calls.log"
  stub_command "gh" "
    echo \"\$*\" >> \"$gh_log\"
    case \"\$*\" in
      *\"pr view\"*\"mergeCommit\"*)
        echo '{\"mergeCommit\":{\"oid\":\"abc123def456\"}}' ;;
      *)
        exit 0 ;;
    esac
  "

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success

  # gh must have been called with 'pr view 392 --json mergeCommit'
  grep -q "pr view 392" "$gh_log" || grep -q "pr view.*392.*mergeCommit" "$gh_log"
}

# ---------------------------------------------------------------------------
# Scenario: implementation_pr が未設定の場合（通常モード）
# WHEN: issue-<N>.json に implementation_pr が存在しない
# THEN: 通常通り本 PR の diff に対して AC チェックを実行する
# ---------------------------------------------------------------------------

@test "ac-verify: no implementation_pr in state → runs without cross-PR gh call" {
  # Ensure no implementation_pr field (default state from setup has none)
  local has_impl_pr
  has_impl_pr="$(jq 'has("implementation_pr")' "$SANDBOX/.autopilot/issues/issue-397.json")"
  [ "$has_impl_pr" = "false" ]

  local gh_log="$SANDBOX/gh_calls.log"
  stub_command "gh" "
    echo \"\$*\" >> \"$gh_log\"
    exit 0
  "

  run bash "$SANDBOX/scripts/chain-runner.sh" ac-verify
  assert_success

  # gh should NOT have been called with 'pr view ... mergeCommit'
  if [ -f "$gh_log" ]; then
    ! grep -q "pr view.*mergeCommit" "$gh_log"
  fi
}

# ===========================================================================
# Requirement: workflow-setup init の retroactive 対応 (MODIFIED)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: retroactive モードでの init 結果 [PENDING]
# WHEN: init が retroactive モードを検出する
# THEN: recommended_action: retroactive_propose が返される
# ---------------------------------------------------------------------------

@test "[PENDING] init: retroactive mode detected → JSON output has recommended_action=retroactive_propose" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  local action
  action="$(echo "$output" | jq -r '.recommended_action // empty' 2>/dev/null)"
  [ "$action" = "retroactive_propose" ]
}

@test "[PENDING] init: retroactive_propose result includes implementation_pr check step" {
  stub_command "git" '
    case "$*" in
      *"branch --show-current"*) echo "feat/397-retroactive" ;;
      *"rev-parse --show-toplevel"*) echo "$SANDBOX" ;;
      *"diff"*"--name-only"*)
        printf "deltaspec/changes/issue-397/specs/retroactive-deltaspec/spec.md\n" ;;
      *) exit 0 ;;
    esac
  '
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json body"*)
        echo "{\"body\": \"No tag.\"}" ;;
      *) exit 0 ;;
    esac
  '

  run bash "$SANDBOX/scripts/chain-runner.sh" init 397
  assert_success

  # Either needs_implementation_pr flag in JSON, or output mentions it
  local needs_check
  needs_check="$(echo "$output" | jq -r '.needs_implementation_pr // empty' 2>/dev/null)"
  [ "$needs_check" = "true" ] || echo "$output" | grep -qi "implementation_pr"
}
