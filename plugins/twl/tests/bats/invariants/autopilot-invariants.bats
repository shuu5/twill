#!/usr/bin/env bats
# autopilot-invariants.bats - Autopilot invariants A through K
#
# Tests the 11 invariant conditions that must always hold true in the
# autopilot system. These are integration-level tests that exercise
# multiple scripts together.

load '../helpers/common'

setup() {
  common_setup
  # Default stubs
  stub_command "tmux" 'exit 1'
  stub_command "gh" 'exit 0'
  stub_command "git" 'exit 0'
}

teardown() {
  common_teardown
}

# ===========================================================================
# Invariant A: State uniqueness (parallel writes yield valid JSON)
# ===========================================================================

@test "invariant-A: parallel writes to same issue produce valid JSON" {
  create_issue_json 1 "running"

  # Run two state-write processes concurrently
  python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --set current_step=step-a &
  local pid1=$!

  python3 -m twl.autopilot.state write \
    --type issue --issue 1 --role worker --set current_step=step-b &
  local pid2=$!

  wait $pid1 || true
  wait $pid2 || true

  # Final state must be valid JSON
  jq '.' "$SANDBOX/.autopilot/issues/issue-1.json" > /dev/null

  # Status must be a valid value
  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [[ "$status" == "running" || "$status" == "merge-ready" || "$status" == "failed" || "$status" == "done" ]]
}

# ===========================================================================
# Invariant B: Worktree delete is pilot-only
# ===========================================================================

@test "invariant-B: worktree-delete rejects worker role (CWD in worktrees/)" {
  mkdir -p "$SANDBOX/worktrees/feat/test-branch"
  cd "$SANDBOX/worktrees/feat/test-branch"

  run bash "$REPO_ROOT/scripts/worktree-delete.sh" "feat/test-branch"

  assert_failure
  assert_output --partial "Worker"
  assert_output --partial "不変条件 B"
}

@test "invariant-B: worktree-delete allows pilot role (CWD in main/)" {
  # Simulate pilot CWD in main/
  mkdir -p "$SANDBOX/main"
  echo "gitdir: ../.bare/worktrees/main" > "$SANDBOX/main/.git"
  mkdir -p "$SANDBOX/.bare/worktrees/main"
  cd "$SANDBOX/main"

  # Set up bare repo detection
  mkdir -p "$SANDBOX/.bare"
  cp "$REPO_ROOT/scripts/worktree-delete.sh" "$SANDBOX/main/scripts/worktree-delete.sh" 2>/dev/null || true
  mkdir -p "$SANDBOX/main/scripts"
  cp "$REPO_ROOT/scripts/worktree-delete.sh" "$SANDBOX/main/scripts/"

  stub_command "git" '
    case "$*" in
      *"worktree remove"*) exit 0 ;;
      *"branch"*)          exit 0 ;;
      *)                   exit 0 ;;
    esac
  '

  run bash "$SANDBOX/main/scripts/worktree-delete.sh" "feat/nonexistent"

  # Should NOT fail with invariant B error
  [[ "$output" != *"Worker"* ]] && [[ "$output" != *"不変条件 B"* ]]
}

@test "invariant-B: Worker chain (chain-steps.sh) does not include worktree-create" {
  # worktree-create は Pilot 専任（不変条件 B）。Worker の chain に含まれてはならない。
  source "$REPO_ROOT/scripts/chain-steps.sh"

  local found=false
  for step in "${CHAIN_STEPS[@]}"; do
    if [[ "$step" == "worktree-create" ]]; then
      found=true
      break
    fi
  done

  [ "$found" = "false" ]
}

# ===========================================================================
# Invariant C: Worker merge prohibition
# ===========================================================================

@test "invariant-C: merge-gate-execute rejects invalid ISSUE (no role check at script level)" {
  # merge-gate-execute は Python 化済み（mergegate.py）
  # --issue に不正な値を渡すと拒否することを確認する
  run python3 -m twl.autopilot.mergegate merge \
    --issue "invalid!" --pr "100" --branch "feat/test"

  assert_failure
  assert_output --partial "不正な"
}

# ===========================================================================
# Invariant D: Dependency fail skip propagation
# ===========================================================================

@test "invariant-D: single dependency fail causes skip" {
  # Issue 2 depends on Issue 1
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
session_id: "test"
repo_mode: "worktree"
project_dir: "/tmp/test"
phases:
  - phase: 1
    - 1
  - phase: 2
    - 2
dependencies:
  2:
  - 1
EOF
  create_issue_json 1 "failed"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 2

  # exit 0 = skip
  assert_success
}

@test "invariant-D: multiple deps with one failed causes skip" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
session_id: "test"
repo_mode: "worktree"
project_dir: "/tmp/test"
phases:
  - phase: 1
    - 1
    - 2
  - phase: 2
    - 3
dependencies:
  3:
  - 1
  - 2
EOF
  create_issue_json 1 "done"
  create_issue_json 2 "failed"

  run bash "$SANDBOX/scripts/autopilot-should-skip.sh" \
    "$SANDBOX/.autopilot/plan.yaml" 3

  # exit 0 = skip
  assert_success
}

# ===========================================================================
# Invariant E: Merge-gate retry limit
# ===========================================================================

@test "invariant-E: first retry allowed (retry_count=0 -> running)" {
  create_issue_json 1 "failed" '.retry_count = 0'

  # _check_pilot_identity() は CWD が worktrees/ 配下なら status 書き込みを拒否するため
  # SANDBOX（worktrees/ 外）に移動してから実行する
  cd "$SANDBOX"
  run python3 -m twl.autopilot.state write \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --type issue --issue 1 --role pilot --set status=running

  assert_success

  local retry
  retry=$(jq -r '.retry_count' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$retry" = "1" ]
}

@test "invariant-E: second retry rejected (retry_count=1)" {
  create_issue_json 1 "failed" '.retry_count = 1'

  cd "$SANDBOX"
  run python3 -m twl.autopilot.state write \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --type issue --issue 1 --role pilot --set status=running

  assert_failure
  assert_output --partial "リトライ上限"
}

# ===========================================================================
# Invariant F: Rebase prohibition (squash merge only)
# ===========================================================================

@test "invariant-F: merge-gate-execute uses --squash flag" {
  # merge-gate-execute は Python 化済み（cli/twl/src/twl/autopilot/mergegate.py）
  # REPO_ROOT = plugins/twl, worktree root = REPO_ROOT/../../
  local mergegate_py
  mergegate_py="$(cd "$REPO_ROOT/../.." && pwd)/cli/twl/src/twl/autopilot/mergegate.py"
  [ -f "$mergegate_py" ] || skip "mergegate.py not found"

  # squash フラグを使用していることを確認
  run grep -c -- '"--squash"' "$mergegate_py"
  assert_success
  [ "$output" -ge 1 ]

  # --rebase フラグは使用していないことを確認（deps.yaml 競合時の rebase は対象外）
  run grep -c -- '"--rebase"' "$mergegate_py"
  [ "$output" = "0" ]
}

# ===========================================================================
# Invariant G: Crash detection guarantee
# ===========================================================================

@test "invariant-G: crash-detect transitions to failed when pane absent" {
  create_issue_json 1 "running"
  stub_command "tmux" 'exit 1'

  # crash-detect.sh は内部で --role pilot の status 書き込みを行う。
  # _check_pilot_identity() は CWD が worktrees/ 配下なら拒否するため
  # SANDBOX（worktrees/ 外）に移動してから実行する。
  cd "$SANDBOX"
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 2 ]

  local new_status
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]
}

# ===========================================================================
# Invariant H: deps.yaml type exclusivity
# ===========================================================================

@test "invariant-H: deps.yaml components have valid types" {
  # Read the real deps.yaml and validate all component types
  local deps_file="$REPO_ROOT/deps.yaml"
  [ -f "$deps_file" ] || skip "deps.yaml not found"

  local valid_types="controller workflow composite atomic specialist reference script"

  # Extract types from component sections only (exclude chain types A/B)
  local types
  types=$(python3 -c "
import yaml
with open('$deps_file') as f:
    data = yaml.safe_load(f)
types = set()
for section in ['skills', 'commands', 'refs', 'scripts', 'agents']:
    for name, comp in data.get(section, {}).items():
        if isinstance(comp, dict) and 'type' in comp:
            types.add(comp['type'])
for t in sorted(types):
    print(t)
")

  for t in $types; do
    local found=false
    for vt in $valid_types; do
      if [ "$t" = "$vt" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = "false" ]; then
      fail "Invalid component type found: $t (allowed: $valid_types)"
    fi
  done
}

# ===========================================================================
# Invariant I: Circular dependency rejection
# ===========================================================================

@test "invariant-I: direct circular dependency (A->B->A) rejected" {
  stub_command "uuidgen" 'echo "12345678-abcd-efgh-ijkl-123456789012"'
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*1*"--json body"*)
        echo "depends on #2" ;;
      *"issue view"*2*"--json body"*)
        echo "depends on #1" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "1 2" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_failure
  assert_output --partial "循環依存"
}

@test "invariant-I: indirect circular dependency (A->B->C->A) rejected" {
  stub_command "uuidgen" 'echo "12345678-abcd-efgh-ijkl-123456789012"'
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json number"*)
        num=$(echo "$*" | grep -oP "\b\d+\b" | tail -1)
        echo "{\"number\": $num}" ;;
      *"issue view"*1*"--json body"*)
        echo "depends on #3" ;;
      *"issue view"*2*"--json body"*)
        echo "depends on #1" ;;
      *"issue view"*3*"--json body"*)
        echo "depends on #2" ;;
      *"api"*"comments"*)
        echo "[]" ;;
      *)
        echo "{}" ;;
    esac
  '

  run bash "$SANDBOX/scripts/autopilot-plan.sh" \
    --issues "1 2 3" \
    --project-dir "$SANDBOX" \
    --repo-mode "worktree"

  assert_failure
  assert_output --partial "循環依存"
}

# ===========================================================================
# Invariant J: Merge前 base drift 検知
# ===========================================================================

# (J のテストは merge-gate 内部で実装済み — ここでは不変条件テーブルとの整合性のみ確認)

@test "invariant-J: ref-invariants.md defines invariant J" {
  run grep -c "^## 不変条件 J:" "$REPO_ROOT/refs/ref-invariants.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-J: silent file deletion (no commit) is detected as base drift" {
  # git stub: diff --diff-filter=D が削除ファイルを返す
  # git stub: log で削除コミットが見つからない → silent deletion として検出
  stub_command "git" '
    case "$*" in
      *"fetch"*)                    exit 0 ;;
      *"diff"*"--diff-filter=D"*)   printf "deleted-file.py\n"; exit 0 ;;
      *"merge-base"*)               printf "abc1234\n"; exit 0 ;;
      *"log"*)                      printf ""; exit 0 ;;
      *)                            exit 0 ;;
    esac
  '

  run python3 -c "
import sys
from twl.autopilot.mergegate import MergeGate, MergeGateError
gate = MergeGate(issue='1', pr_number='100', branch='feat/test')
try:
    gate._check_base_drift()
    sys.exit(0)
except MergeGateError:
    sys.exit(1)
"
  assert_failure
}

@test "invariant-J: intentional deletion (has commit) is not flagged" {
  # git stub: diff --diff-filter=D が削除ファイルを返す
  # git stub: log で削除コミットが見つかる → 意図的削除として無視
  stub_command "git" '
    case "$*" in
      *"fetch"*)                    exit 0 ;;
      *"diff"*"--diff-filter=D"*)   printf "deleted-file.py\n"; exit 0 ;;
      *"merge-base"*)               printf "abc1234\n"; exit 0 ;;
      *"log"*)                      printf "def5678\n"; exit 0 ;;
      *)                            exit 0 ;;
    esac
  '

  run python3 -c "
import sys
from twl.autopilot.mergegate import MergeGate, MergeGateError
gate = MergeGate(issue='1', pr_number='100', branch='feat/test')
try:
    gate._check_base_drift()
    sys.exit(0)
except MergeGateError:
    sys.exit(1)
"
  assert_success
}

# ===========================================================================
# Invariant K: Pilot implementation prohibition
# ===========================================================================

@test "invariant-K: ref-invariants.md defines invariant K (Pilot 実装禁止)" {
  run grep -c "^## 不変条件 K:" "$REPO_ROOT/refs/ref-invariants.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-K: co-autopilot SKILL.md MUST NOT section prohibits Pilot direct implementation" {
  run grep -c "Pilot.*Worker.*直接実装\|Agent(Implement" "$REPO_ROOT/skills/co-autopilot/SKILL.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-K: co-autopilot SKILL.md references invariant K in MUST NOT" {
  run grep -c "不変条件 K" "$REPO_ROOT/skills/co-autopilot/SKILL.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-K: SKILL.md invariant list includes K" {
  # 不変条件一覧に K=Pilot 実装禁止 が含まれること
  run grep "K=Pilot" "$REPO_ROOT/skills/co-autopilot/SKILL.md"
  assert_success
}

@test "invariant-K: pilot cannot write implementation-only field (current_step)" {
  # _check_rbac(): role=pilot は current_step への書き込みを拒否する
  create_issue_json 1 "running"
  run python3 -m twl.autopilot.state write \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --type issue --issue 1 --role pilot --set current_step=change-apply
  assert_failure
  assert_output --partial "current_step"
}

@test "invariant-K: worker can write implementation-only field (current_step)" {
  # _check_rbac(): role=worker は current_step への書き込みを許可する
  create_issue_json 1 "running"
  run python3 -m twl.autopilot.state write \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --type issue --issue 1 --role worker --set current_step=change-apply
  assert_success
}

# ===========================================================================
# Invariant L: autopilot マージ実行責務
# ===========================================================================

@test "invariant-L: ref-invariants.md defines invariant L (autopilot マージ実行責務)" {
  run grep -c "^## 不変条件 L:" "$REPO_ROOT/refs/ref-invariants.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-L: auto-merge.sh sets merge-ready without merging in autopilot mode" {
  # autopilot 配下（status=running）では gh pr merge を呼ばず merge-ready 宣言のみ行う
  create_issue_json 1 "running"

  # gh pr merge が呼ばれた場合はテスト失敗とする（不変条件 L 違反）
  stub_command "gh" '
    case "$*" in
      *"pr merge"*) echo "INVARIANT-VIOLATION: gh pr merge called in autopilot mode" >&2; exit 1 ;;
      *) exit 0 ;;
    esac
  '

  cd "$SANDBOX"
  run bash "$SANDBOX/scripts/auto-merge.sh" \
    --issue 1 --pr 100 --branch "feat/test"

  assert_success

  local status
  status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$status" = "merge-ready" ]
}

# ===========================================================================
# Invariant M: chain 遷移は orchestrator/手動 inject のみ
# ===========================================================================

@test "invariant-M: ref-invariants.md defines invariant M (chain 遷移制限)" {
  run grep -c "^## 不変条件 M:" "$REPO_ROOT/refs/ref-invariants.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-M: co-autopilot SKILL.md prohibits direct Pilot nudge (不変条件 M)" {
  run grep -c "不変条件 M" "$REPO_ROOT/skills/co-autopilot/SKILL.md"
  assert_success
  [ "$output" -ge 1 ]
}

@test "invariant-M: inject-next-workflow.sh validates workflow skill name against allow-list" {
  # inject_next_workflow() はコマンドインジェクション防止のため allow-list で
  # /twl:workflow-<kebab> 形式のみを許可する（不変条件 M）
  local inject_lib="$REPO_ROOT/scripts/lib/inject-next-workflow.sh"
  [ -f "$inject_lib" ] || skip "inject-next-workflow.sh not found"

  run grep -cF '/twl:workflow-[a-z]' "$inject_lib"
  assert_success
  [ "$output" -ge 1 ]
}
