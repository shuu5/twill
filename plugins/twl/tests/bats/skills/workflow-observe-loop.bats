#!/usr/bin/env bats
# workflow-observe-loop.bats - structural validation of workflow-observe-loop

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Case 1: skeleton 検証 (SKILL.md が frontmatter + Step 1-4 を含む)
# ---------------------------------------------------------------------------

@test "workflow-observe-loop: SKILL.md exists with correct frontmatter" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  [ -f "$skill_md" ]
  grep -q 'name: twl:workflow-observe-loop' "$skill_md"
  grep -q 'type: workflow' "$skill_md"
  grep -q 'effort: high' "$skill_md"
  grep -q 'spawnable_by:' "$skill_md"
  grep -q '- controller' "$skill_md"
}

@test "workflow-observe-loop: SKILL.md contains Step 1-4" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  grep -q '### Step 1' "$skill_md"
  grep -q '### Step 2' "$skill_md"
  grep -q '### Step 3' "$skill_md"
  grep -q '### Step 4' "$skill_md"
}

# ---------------------------------------------------------------------------
# Case 2: 自 window 拒否ロジック明記
# ---------------------------------------------------------------------------

@test "workflow-observe-loop: self-window rejection documented" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  grep -q '自 window' "$skill_md"
  grep -q 'exit 2' "$skill_md"
}

# ---------------------------------------------------------------------------
# Case 3: bash ループ実装が MUST として明記
# ---------------------------------------------------------------------------

@test "workflow-observe-loop: bash loop implementation is MUST" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  run grep -c 'MUST.*bash' "$skill_md"
  assert [ "$output" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Case 4: MUST NOT 4 件以上
# ---------------------------------------------------------------------------

@test "workflow-observe-loop: at least 4 MUST NOT items" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  local count
  count=$(grep -c '^\- ' <(sed -n '/禁止事項/,$ p' "$skill_md"))
  [ "$count" -ge 4 ]
}

# ---------------------------------------------------------------------------
# Case 5: context budget (200 行以内)
# ---------------------------------------------------------------------------

@test "workflow-observe-loop: SKILL.md is within 200 lines" {
  local skill_md="$REPO_ROOT/skills/workflow-observe-loop/SKILL.md"
  local lines
  lines=$(wc -l < "$skill_md")
  [ "$lines" -le 200 ]
}
