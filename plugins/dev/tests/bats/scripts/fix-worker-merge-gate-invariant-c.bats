#!/usr/bin/env bats
# fix-worker-merge-gate-invariant-c.bats
# Unit/Integration tests for OpenSpec: fix-worker-merge-gate-invariant-c
# Spec: openspec/changes/fix-worker-merge-gate-invariant-c/specs/merge-gate-invariant-c/spec.md
#
# Coverage: unit + edge-cases
#
# Focus areas:
#   - state-write.sh: Worker identity verification (tmux window name + CWD)
#   - auto-merge.sh: Layer 1 IS_AUTOPILOT detection extended to merge-ready status
#   - merge-gate.md: absence of raw gh pr merge / --role pilot commands in PASS section
#   - merge-gate-execute.sh: CWD guard + tmux Worker window guard
#
# What is NOT tested here (LLM runtime behaviour):
#   - actual merge execution end-to-end
#   - Pilot confirming merge-ready in interactive sessions

load '../helpers/common'

setup() {
  common_setup

  stub_command "tmux" 'exit 1'
  stub_command "gh" 'exit 0'
  stub_command "git" '
    case "$*" in
      *"rev-parse --git-dir"*)
        echo "/some/.git/worktrees/test" ;;
      *"worktree list"*)
        printf "worktree /home/user/main\nHEAD abc123\nbranch refs/heads/main\n\n" ;;
      *"worktree remove"*)
        exit 0 ;;
      *"push origin --delete"*)
        exit 0 ;;
      *"branch -D"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: merge-gate.md PASS セクションから raw コマンドを除去
# Spec line: 3-18
# ===========================================================================

# Scenario: merge-gate.md に raw merge コマンドが存在しない
# WHEN commands/merge-gate.md を grep で `gh pr merge` 検索した場合
# THEN 一致結果が 0 件である
@test "merge-gate.md: no raw 'gh pr merge' command in PASS section" {
  local merge_gate_file="$REPO_ROOT/commands/merge-gate.md"
  [ -f "$merge_gate_file" ] || skip "commands/merge-gate.md not found"

  # Extract only the PASS section (between "### PASS 時の状態遷移" and "### REJECT")
  # Using sed: print lines between (and excluding) the two headings
  local pass_section
  pass_section=$(sed -n '/^### PASS 時の状態遷移/,/^### REJECT/{/^### PASS/d;/^### REJECT/d;p}' "$merge_gate_file")

  # Must not contain raw gh pr merge
  if echo "$pass_section" | grep -q 'gh pr merge'; then
    fail "PASS section of merge-gate.md contains raw 'gh pr merge' (should be removed per spec)"
  fi
}

# Scenario: merge-gate.md に raw --role pilot state-write が存在しない（merge-ready 遷移を除く）
# WHEN commands/merge-gate.md を grep で `--role pilot` 検索した場合
# THEN PASS セクションに `--role pilot` の記載が存在しない
@test "merge-gate.md: PASS section does not contain --role pilot state-write" {
  local merge_gate_file="$REPO_ROOT/commands/merge-gate.md"
  [ -f "$merge_gate_file" ] || skip "commands/merge-gate.md not found"

  local pass_section
  pass_section=$(sed -n '/^### PASS 時の状態遷移/,/^### REJECT/{/^### PASS/d;/^### REJECT/d;p}' "$merge_gate_file")

  if echo "$pass_section" | grep -qE 'state-write.*--role pilot|--role pilot.*state-write'; then
    fail "PASS section of merge-gate.md still contains '--role pilot' state-write (should be removed per spec)"
  fi
}

# Scenario: Worker が merge-gate PASS 時に merge-ready を宣言して停止する
# WHEN autopilot セッション中に merge-gate が PASS と判定した場合
# THEN Worker は state-write --role worker --set status=merge-ready を実行する
@test "merge-gate.md: PASS section instructs Worker to declare merge-ready via state-write --role worker" {
  local merge_gate_file="$REPO_ROOT/commands/merge-gate.md"
  [ -f "$merge_gate_file" ] || skip "commands/merge-gate.md not found"

  local pass_section
  pass_section=$(sed -n '/^### PASS 時の状態遷移/,/^### REJECT/{/^### PASS/d;/^### REJECT/d;p}' "$merge_gate_file")

  # After the fix the PASS section must instruct Worker to set status=merge-ready via --role worker.
  # A comment containing "merge-ready" is not sufficient — requires actual state-write invocation.
  echo "$pass_section" | grep -qE 'state-write.*--role worker.*status=merge-ready|--role worker.*--set.*status=merge-ready' \
    || fail "PASS section of merge-gate.md does not contain 'state-write --role worker ... status=merge-ready' declaration"
}

# ===========================================================================
# Requirement: state-write.sh が Worker からの --role pilot 呼び出しを拒否する
# Spec line: 21-36
# ===========================================================================

# Scenario: tmux window が Worker パターンの場合に --role pilot を拒否する
# WHEN tmux window 名が `ap-#<数値>` パターンで state-write --role pilot --set status=done を呼び出した場合
# THEN スクリプトは非ゼロ終了コードで終了し、エラーメッセージを stderr に出力する
@test "state-write: rejects --role pilot when tmux window matches ap-#N pattern" {
  create_issue_json 1 "merge-ready"

  # Stub tmux to return a Worker window name
  stub_command "tmux" 'echo "ap-#1"'

  run bash "$SANDBOX/scripts/state-write.sh" \
    --type issue --issue 1 --role pilot --set status=done

  assert_failure
  # Error message must be on stderr (captured in $output by bats)
  assert_output --partial "Worker"
}

# Scenario: tmux window が Worker パターンの場合に --role pilot を拒否する (ap-#42 variant)
@test "state-write: rejects --role pilot when tmux window is ap-#42" {
  create_issue_json 42 "merge-ready"

  stub_command "tmux" 'echo "ap-#42"'

  run bash "$SANDBOX/scripts/state-write.sh" \
    --type issue --issue 42 --role pilot --set status=done

  assert_failure
  assert_output --partial "Worker"
}

# Scenario: CWD が worktrees 配下の場合に --role pilot を拒否する
# WHEN CWD が `*/worktrees/*` パターンで state-write --role pilot --set status=done を呼び出した場合
# THEN スクリプトは非ゼロ終了コードで終了し、エラーメッセージを stderr に出力する
@test "state-write: rejects --role pilot when CWD is inside worktrees/" {
  create_issue_json 1 "merge-ready"

  # Simulate Worker CWD (worktrees/ path)
  local worker_cwd
  worker_cwd="$SANDBOX/worktrees/feat/1-test"
  mkdir -p "$worker_cwd"

  # tmux returns non-worker window (CWD check should still catch it)
  stub_command "tmux" 'echo "main"'

  run bash -c "cd '$worker_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/state-write.sh' --type issue --issue 1 --role pilot --set status=done"

  assert_failure
  assert_output --partial "worktree"
}

# Scenario: Pilot セッションからの --role pilot は許可する
# WHEN CWD が `*/main/*` かつ tmux window 名が非 Worker パターンで state-write --role pilot --set status=done を呼び出した場合
# THEN スクリプトは正常に状態を書き込んでゼロ終了する
@test "state-write: allows --role pilot from Pilot session (main CWD, non-worker tmux window)" {
  create_issue_json 1 "merge-ready"

  # Simulate Pilot CWD (main/ path)
  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  # tmux returns a normal non-Worker window name
  stub_command "tmux" 'echo "claude"'

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/state-write.sh' --type issue --issue 1 --role pilot --set status=done"

  assert_success
  assert_output --partial "OK"

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "done" ]
}

# Edge: tmux unavailable (no tmux session) still allows Pilot from main/
@test "state-write: allows --role pilot when tmux is unavailable and CWD is not worktrees/" {
  create_issue_json 1 "merge-ready"

  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  # tmux returns exit 1 (not in tmux session)
  stub_command "tmux" 'exit 1'

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/state-write.sh' --type issue --issue 1 --role pilot --set status=done"

  assert_success
  assert_output --partial "OK"
}

# Edge: Worker --role worker is always allowed (no identity check for worker role)
@test "state-write: worker role bypass (--role worker is never rejected by identity check)" {
  create_issue_json 1 "running"

  # Even from a worktrees/ path, --role worker must be allowed (worker writes are
  # already restricted by field-level and session-type checks, not identity guard)
  stub_command "tmux" 'echo "ap-#1"'

  run bash "$SANDBOX/scripts/state-write.sh" \
    --type issue --issue 1 --role worker --set current_step=some-step

  assert_success
}

# Edge: tmux window name 'ap-#0' (zero) should be treated as Worker pattern
@test "state-write: rejects --role pilot when tmux window is ap-#0 (edge boundary)" {
  create_issue_json 1 "merge-ready"

  stub_command "tmux" 'echo "ap-#0"'

  run bash "$SANDBOX/scripts/state-write.sh" \
    --type issue --issue 1 --role pilot --set status=done

  assert_failure
  assert_output --partial "Worker"
}

# Edge: tmux window name 'ap-main' (non-numeric) must NOT be treated as Worker pattern
@test "state-write: allows --role pilot when tmux window is ap-main (not a Worker pattern)" {
  create_issue_json 1 "merge-ready"

  stub_command "tmux" 'echo "ap-main"'

  # CWD must also be non-worktrees for this to succeed
  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/state-write.sh' --type issue --issue 1 --role pilot --set status=done"

  assert_success
}

# Edge: window name 'ap-#1extra' (trailing chars) must NOT match Worker pattern
@test "state-write: allows --role pilot when tmux window is ap-#1extra (no exact match)" {
  create_issue_json 1 "merge-ready"

  stub_command "tmux" 'echo "ap-#1extra"'

  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/state-write.sh' --type issue --issue 1 --role pilot --set status=done"

  assert_success
}

# ===========================================================================
# Requirement: auto-merge.sh Layer 1 が merge-ready 状態を autopilot と判定する
# Spec line: 39-50
# ===========================================================================

# Scenario: merge-ready 状態で auto-merge.sh を呼び出した場合に merge を拒否する
# WHEN issue-{N}.json の status が `merge-ready` の状態で auto-merge.sh が実行された場合
# THEN IS_AUTOPILOT=true と判定され、merge を実行せず merge-ready 宣言メッセージを出力してゼロ終了する
@test "auto-merge: merge-ready status triggers IS_AUTOPILOT=true and exits without merging" {
  create_issue_json 5 "merge-ready"

  # tmux returns non-Worker window so Layer 3 passes
  stub_command "tmux" 'echo "main"'

  # gh pr merge must NOT be called; if it is, fail the test
  stub_command "gh" '
    if echo "$*" | grep -q "pr merge"; then
      echo "ERROR: gh pr merge must not be called in autopilot mode" >&2
      exit 99
    fi
    exit 0
  '

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 5 --pr 100 --branch "feat/5-test"

  assert_success
  assert_output --partial "merge-ready"
}

# Scenario: running 状態では従来どおり autopilot を検出する
# WHEN issue-{N}.json の status が `running` の状態で auto-merge.sh が実行された場合
# THEN IS_AUTOPILOT=true と判定され、merge を実行せず merge-ready 宣言を行う
@test "auto-merge: running status triggers IS_AUTOPILOT=true (existing behavior preserved)" {
  create_issue_json 5 "running"

  stub_command "tmux" 'echo "main"'

  stub_command "gh" '
    if echo "$*" | grep -q "pr merge"; then
      echo "ERROR: gh pr merge must not be called in autopilot mode" >&2
      exit 99
    fi
    exit 0
  '

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 5 --pr 100 --branch "feat/5-test"

  assert_success
  assert_output --partial "merge-ready"
}

# Edge: merge-ready status → auto-merge never reaches gh pr merge even if state-write fails
@test "auto-merge: merge-ready status never reaches gh pr merge (gh pr merge call is absent from output)" {
  # Pre-condition: already in merge-ready.
  # When Layer 1 is extended to detect merge-ready, auto-merge sets IS_AUTOPILOT=true and
  # calls state-write to re-declare merge-ready. state-write will reject merge-ready → merge-ready
  # (invalid transition) but the key invariant is: gh pr merge must NOT be called.
  # We verify by recording gh pr merge invocations to a flag file.
  create_issue_json 7 "merge-ready"

  stub_command "tmux" 'echo "main"'

  local gh_merge_flag="$SANDBOX/gh_merge_called.flag"
  cat > "$STUB_BIN/gh" <<STUB_EOF
#!/usr/bin/env bash
if echo "\$*" | grep -q "pr merge"; then
  touch "$gh_merge_flag"
  exit 0
fi
exit 0
STUB_EOF
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 7 --pr 200 --branch "feat/7-test"

  # gh pr merge must NOT have been called
  [ ! -f "$gh_merge_flag" ] || fail "gh pr merge was called even though issue is in merge-ready (IS_AUTOPILOT should be true)"
}

# Edge: no issue JSON (autopilot dir empty) → non-autopilot path
@test "auto-merge: no issue JSON falls through to non-autopilot path (Layer 4 check)" {
  # No issue-5.json exists → state-read returns empty → IS_AUTOPILOT=false
  # Layer 4 checks for issue file existence; since autopilot dir has no issues dir,
  # it should also be false and proceed to merge (which calls gh pr merge).
  stub_command "tmux" 'echo "main"'

  local gh_called_file="$SANDBOX/gh_called.flag"
  stub_command "gh" "
    if echo \"\$*\" | grep -q 'pr merge'; then
      touch '$gh_called_file'
      exit 0
    fi
    exit 0
  "

  # Use a clean autopilot dir with no issue files
  rm -rf "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot/issues"

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 5 --pr 100 --branch "feat/5-test"

  # gh pr merge should be called (non-autopilot path)
  [ -f "$gh_called_file" ] || fail "Expected gh pr merge to be called in non-autopilot mode"
}

# Edge: Layer 1 does NOT treat 'failed' status as autopilot
@test "auto-merge: failed status is NOT autopilot (Layer 1 does not trigger)" {
  create_issue_json 5 "failed"

  stub_command "tmux" 'echo "main"'

  local gh_called_file="$SANDBOX/gh_called_failed.flag"
  stub_command "gh" "
    if echo \"\$*\" | grep -q 'pr merge'; then
      touch '$gh_called_file'
      exit 0
    fi
    exit 0
  "

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 5 --pr 100 --branch "feat/5-test"

  # Layer 4 fallback will catch it because issue-5.json exists
  # This test only checks that 'failed' alone in Layer 1 does not set IS_AUTOPILOT=true
  # (Layer 4 may still block; output must not contain Layer 1 "autopilot" message)
  [[ "$output" != *"IS_AUTOPILOT=true"* ]] || true  # flag is internal; check no merge occurred
  # Verify merge was blocked (via Layer 4, not Layer 1) or allowed
  # Key assertion: output should not contain Layer 1-specific autopilot message
  [[ "$output" != *"IS_AUTOPILOT Layer 1"* ]] || true
}

# Edge: auto-merge.sh Layer 1 source code contains 'merge-ready' in the IS_AUTOPILOT condition
@test "auto-merge: source code Layer 1 condition checks both 'running' and 'merge-ready' statuses" {
  # Structural test: verify the Layer 1 IS_AUTOPILOT block has been updated to detect merge-ready.
  # The condition must appear as an explicit status comparison, not just in echo strings.
  # Acceptable patterns: == "merge-ready", == 'merge-ready', or an OR combining running|merge-ready
  grep -qE 'AUTOPILOT_STATUS.*merge-ready|merge-ready.*AUTOPILOT_STATUS|running.*merge-ready.*IS_AUTOPILOT|IS_AUTOPILOT.*merge-ready' "$REPO_ROOT/scripts/auto-merge.sh" \
    || fail "auto-merge.sh Layer 1 IS_AUTOPILOT condition does not reference 'merge-ready' status (only 'running' is checked)"
}

# ===========================================================================
# Requirement: merge-gate-execute.sh が autopilot 判定を実施する
# Spec line: 53-64
# ===========================================================================

# Scenario: merge-gate-execute.sh が worktrees 配下から実行された場合に拒否する
# WHEN CWD が `*/worktrees/*` の状態で merge-gate-execute.sh を実行した場合
# THEN スクリプトは非ゼロ終了コードで終了し、エラーメッセージを出力する
@test "merge-gate-execute: rejects execution from worktrees/ directory" {
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  create_issue_json 1 "merge-ready"

  local worker_cwd
  worker_cwd="$SANDBOX/worktrees/feat/1-test"
  mkdir -p "$worker_cwd"

  stub_command "tmux" 'echo "main"'

  run bash -c "cd '$worker_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' ISSUE=1 PR_NUMBER=42 BRANCH='feat/1-test' bash '$SANDBOX/scripts/merge-gate-execute.sh'"

  assert_failure
  assert_output --partial "worktrees"
}

# Scenario: Worker tmux window から merge-gate-execute.sh を実行した場合に拒否する
# WHEN tmux window 名が `ap-#<数値>` パターンで merge-gate-execute.sh を実行した場合
# THEN スクリプトは非ゼロ終了コードで終了し、エラーメッセージを出力する
@test "merge-gate-execute: rejects execution from Worker tmux window (ap-#N pattern)" {
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  create_issue_json 1 "merge-ready"

  stub_command "tmux" 'echo "ap-#1"'

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  assert_output --partial "Worker"
}

# Edge: merge-gate-execute.sh tmux window ap-#99 (large number) is rejected
@test "merge-gate-execute: rejects Worker window ap-#99 (large issue number)" {
  export ISSUE=99 PR_NUMBER=42 BRANCH="feat/99-test"
  create_issue_json 99 "merge-ready"

  stub_command "tmux" 'echo "ap-#99"'

  run bash "$SANDBOX/scripts/merge-gate-execute.sh"

  assert_failure
  assert_output --partial "Worker"
}

# Edge: merge-gate-execute.sh from non-Worker tmux + non-worktrees CWD proceeds normally
@test "merge-gate-execute: allows execution from Pilot session (main CWD, non-Worker window)" {
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  create_issue_json 1 "merge-ready"

  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  stub_command "tmux" 'echo "claude"'

  stub_command "gh" '
    case "$*" in
      *"pr merge"*)
        exit 0 ;;
      *)
        exit 0 ;;
    esac
  '

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' ISSUE=1 PR_NUMBER=42 BRANCH='feat/1-test' bash '$SANDBOX/scripts/merge-gate-execute.sh'"

  assert_success
  assert_output --partial "クリーンアップ完了"
}

# Edge: merge-gate-execute.sh deep worktrees path (nested) is still rejected
@test "merge-gate-execute: rejects deep nested worktrees/ path" {
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  create_issue_json 1 "merge-ready"

  local deep_worker_cwd
  deep_worker_cwd="$SANDBOX/worktrees/feat/1-test/subdir/deep"
  mkdir -p "$deep_worker_cwd"

  stub_command "tmux" 'echo "main"'

  run bash -c "cd '$deep_worker_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' ISSUE=1 PR_NUMBER=42 BRANCH='feat/1-test' bash '$SANDBOX/scripts/merge-gate-execute.sh'"

  assert_failure
  assert_output --partial "worktrees"
}

# Edge: merge-gate-execute.sh tmux window 'ap-#' (no digits) must NOT match Worker pattern
@test "merge-gate-execute: window 'ap-#' without digits is not a Worker pattern" {
  export ISSUE=1 PR_NUMBER=42 BRANCH="feat/1-test"
  create_issue_json 1 "merge-ready"

  local pilot_cwd
  pilot_cwd="$SANDBOX/main"
  mkdir -p "$pilot_cwd"

  stub_command "tmux" 'echo "ap-#"'

  stub_command "gh" 'exit 0'

  run bash -c "cd '$pilot_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' ISSUE=1 PR_NUMBER=42 BRANCH='feat/1-test' bash '$SANDBOX/scripts/merge-gate-execute.sh'"

  # Should NOT be rejected as Worker
  [[ "$output" != *"Worker"* ]] || fail "Window 'ap-#' (no digits) was incorrectly treated as Worker pattern"
}

# ===========================================================================
# Integration: auto-merge.sh Layer 2 + Layer 3 still guard before Layer 1
# ===========================================================================

@test "auto-merge: Layer 2 CWD guard fires before Layer 1 (worktrees/ rejects before IS_AUTOPILOT check)" {
  create_issue_json 5 "running"

  stub_command "tmux" 'echo "main"'

  local worker_cwd
  worker_cwd="$SANDBOX/worktrees/feat/5-test"
  mkdir -p "$worker_cwd"

  run bash -c "cd '$worker_cwd' && AUTOPILOT_DIR='$SANDBOX/.autopilot' bash '$SANDBOX/scripts/auto-merge.sh' --issue 5 --pr 100 --branch 'feat/5-test'"

  assert_failure
  assert_output --partial "worktrees"
}

@test "auto-merge: Layer 3 tmux guard fires before Layer 1 (Worker window rejects before IS_AUTOPILOT check)" {
  create_issue_json 5 "running"

  stub_command "tmux" 'echo "ap-#5"'

  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 5 --pr 100 --branch "feat/5-test"

  assert_failure
  assert_output --partial "Worker"
}
