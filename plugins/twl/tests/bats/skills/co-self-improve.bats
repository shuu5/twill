#!/usr/bin/env bats
# co-self-improve.bats - structural validation of co-self-improve controller

load '../helpers/common'

setup() {
  common_setup
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Case 1: ファイル存在確認
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md exists" {
  [ -f "$REPO_ROOT/skills/co-self-improve/SKILL.md" ]
}

# ---------------------------------------------------------------------------
# Case 2: frontmatter 検証
# ---------------------------------------------------------------------------

@test "co-self-improve: frontmatter contains name=twl:co-self-improve" {
  grep -q 'name: twl:co-self-improve' "$REPO_ROOT/skills/co-self-improve/SKILL.md"
}

@test "co-self-improve: frontmatter contains type=controller" {
  grep -q 'type: controller' "$REPO_ROOT/skills/co-self-improve/SKILL.md"
}

@test "co-self-improve: frontmatter contains effort=high" {
  grep -q 'effort: high' "$REPO_ROOT/skills/co-self-improve/SKILL.md"
}

# ---------------------------------------------------------------------------
# Case 3: deps.yaml 整合
# ---------------------------------------------------------------------------

@test "co-self-improve: deps.yaml entry type is controller" {
  local type
  type=$(yq '.skills."co-self-improve".type' "$REPO_ROOT/deps.yaml")
  [ "$type" = "controller" ]
}

@test "co-self-improve: deps.yaml entry has 11 calls" {
  local count
  count=$(yq '.skills."co-self-improve".calls | length' "$REPO_ROOT/deps.yaml")
  [ "$count" -eq 12 ]
}

# ---------------------------------------------------------------------------
# Case 4: Step 列挙（Step 0 ~ Step 5 = 6 セクション以上）
# ---------------------------------------------------------------------------

@test "co-self-improve: SKILL.md has at least 6 Step sections" {
  local count
  count=$(grep -c '^## Step' "$REPO_ROOT/skills/co-self-improve/SKILL.md")
  [ "$count" -ge 6 ]
}
