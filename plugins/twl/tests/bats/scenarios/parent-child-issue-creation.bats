#!/usr/bin/env bats
# parent-child-issue-creation.bats
# BDD tests for OpenSpec: co-issue-cross-repo-split / parent-child-issue-creation
# Spec: openspec/changes/co-issue-cross-repo-split/specs/parent-child-issue-creation.md
#
# Coverage: happy-path + edge-cases
#
# What is tested (all BATS-verifiable, structure/content level):
#   - SKILL.md: Phase 4 describes parent Issue creation on cross-repo split
#   - SKILL.md: parent Issue body includes "概要" and "子 Issue" sections
#   - SKILL.md: parent Issue title has [Feature] prefix
#   - SKILL.md: child Issues created per-repo with gh issue create -R owner/repo
#   - SKILL.md: child Issue body includes Parent: owner/repo#N reference
#   - SKILL.md: child Issue title includes repo name
#   - SKILL.md: creation order is parent → children → checklist update
#   - SKILL.md: checklist format is - [ ] owner/repo#N
#   - SKILL.md: child Issue creation failure is non-fatal (warning, continue)
#   - SKILL.md: failed child Issues are excluded from checklist
#   - SKILL.md: non-split path uses existing issue-create / issue-bulk-create
#
# What is NOT tested here (LLM runtime behaviour):
#   - actual gh CLI invocations
#   - real GitHub API responses
#   - race conditions in parallel Issue creation

load '../helpers/common'

setup() {
  common_setup
  SKILL_FILE="$REPO_ROOT/skills/co-issue/SKILL.md"
  DEPS_FILE="$REPO_ROOT/deps.yaml"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: parent Issue の生成
# Spec: openspec/changes/co-issue-cross-repo-split/specs/parent-child-issue-creation.md
# ---------------------------------------------------------------------------

# Scenario: parent Issue を作成する
# WHEN クロスリポ分割が承認され Phase 4 に到達する
# THEN 現在のリポに parent Issue が作成され、タイトルに [Feature] プレフィックスが付き、
#      body に「概要」「子 Issue」セクションが含まれる
@test "parent-issue: SKILL.md Phase 4 describes parent Issue creation on cross-repo split" {
  local phase4_section
  phase4_section=$(awk '/^## Phase 4/,/^## [^#]/' "$SKILL_FILE")
  echo "$phase4_section" | grep -qiE 'parent.*issue|parent Issue|親.*Issue' \
    || fail "Parent Issue creation not described in Phase 4 of SKILL.md"
}

@test "parent-issue: SKILL.md specifies [Feature] prefix for parent Issue title" {
  grep -qE '\[Feature\]' "$SKILL_FILE" \
    || fail "[Feature] title prefix for parent Issue not mentioned in SKILL.md"
}

@test "parent-issue: SKILL.md parent Issue body includes 概要 section" {
  grep -q '概要' "$SKILL_FILE" \
    || fail "概要 section for parent Issue body not mentioned in SKILL.md"
}

@test "parent-issue: SKILL.md parent Issue body includes 子 Issue section" {
  grep -qE '子 Issue|子Issue|child.*issue.*section' "$SKILL_FILE" \
    || fail "子 Issue section for parent Issue body not mentioned in SKILL.md"
}

# Scenario: parent Issue に子 Issue チェックリストを追記する
# WHEN 全ての子 Issue 作成が完了する
# THEN parent Issue の body 内「子 Issue」セクションに - [ ] owner/repo#N 形式のチェックリストが追記される
@test "parent-issue: SKILL.md specifies checklist format - [ ] owner/repo#N" {
  grep -qE '\- \[ \].*owner.*repo|checklist.*owner/repo|owner/repo#' "$SKILL_FILE" \
    || fail "Checklist format '- [ ] owner/repo#N' not specified in SKILL.md"
}

@test "parent-issue: SKILL.md describes updating parent Issue after children are created" {
  # The update/追記 step must appear after child creation description
  grep -qiE '追記|update.*parent|parent.*update|checklist.*追記' "$SKILL_FILE" \
    || fail "Parent Issue checklist update step not described in SKILL.md"
}

# ---------------------------------------------------------------------------
# Requirement: 子 Issue のリポ別作成
# Spec: openspec/changes/co-issue-cross-repo-split/specs/parent-child-issue-creation.md
# ---------------------------------------------------------------------------

# Scenario: 3リポに子 Issue を作成する
# WHEN 対象リポが loom, loom-plugin-dev, loom-plugin-session の3つである
# THEN 各リポに1つずつ子 Issue が作成され、合計3つの子 Issue が存在する
@test "child-issues: SKILL.md uses gh issue create -R owner/repo for cross-repo child Issues" {
  grep -qE 'gh issue create.*-R|-R.*gh issue create|issue create.*-R' "$SKILL_FILE" \
    || fail "gh issue create -R owner/repo pattern not described in SKILL.md"
}

@test "child-issues: SKILL.md describes per-repo child Issue creation (one per repo)" {
  grep -qiE '各リポ.*Issue|per.repo.*issue|child.*issue.*each.*repo|リポ.*子.*Issue' "$SKILL_FILE" \
    || fail "Per-repo child Issue creation not described in SKILL.md"
}

# Scenario: 子 Issue の body に parent 参照を含める
# WHEN 子 Issue が作成される
# THEN 子 Issue の body に Parent: owner/repo#N 形式で parent Issue への参照が含まれる
@test "child-issues: SKILL.md specifies Parent: owner/repo#N reference in child Issue body" {
  grep -qE 'Parent:.*owner.*repo|Parent:.*#' "$SKILL_FILE" \
    || fail "Parent: owner/repo#N reference format not specified in SKILL.md"
}

# Scenario: 子 Issue のタイトルにリポ名を含める
# WHEN 子 Issue が作成される
# THEN 子 Issue のタイトルに対象リポ名が含まれ、parent Issue タイトルとの関連が明確である
@test "child-issues: SKILL.md specifies repo name in child Issue title" {
  grep -qiE 'リポ名.*タイトル|タイトル.*リポ名|child.*title.*repo|repo.*name.*title' "$SKILL_FILE" \
    || fail "Repo name in child Issue title not specified in SKILL.md"
}

# ---------------------------------------------------------------------------
# Requirement: Phase 4 一括作成フローの拡張
# Spec: openspec/changes/co-issue-cross-repo-split/specs/parent-child-issue-creation.md
# ---------------------------------------------------------------------------

# Scenario: クロスリポ分割時の作成順序
# WHEN クロスリポ分割が承認されている
# THEN parent Issue → 子 Issue（リポ順）→ parent Issue へのチェックリスト追記 の順で実行される
@test "phase4-flow: SKILL.md creation order is parent then children then checklist update" {
  # Verify the ordering is described: parent first, then children, then checklist
  local phase4_content
  phase4_content=$(awk '/## Phase 4/,0' "$SKILL_FILE")

  local parent_line child_line checklist_line
  parent_line=$(echo "$phase4_content" | grep -n 'parent.*issue\|parent Issue\|親.*Issue' -i | head -1 | cut -d: -f1)
  child_line=$(echo "$phase4_content" | grep -n '子.*issue\|child.*issue' -i | head -1 | cut -d: -f1)
  checklist_line=$(echo "$phase4_content" | grep -n 'checklist\|チェックリスト.*追記\|追記' -i | head -1 | cut -d: -f1)

  [ -n "$parent_line" ] || fail "Parent Issue creation step not found in Phase 4"
  [ -n "$child_line" ]  || fail "Child Issue creation step not found in Phase 4"
  [ -n "$checklist_line" ] || fail "Checklist update step not found in Phase 4"

  [ "$parent_line" -lt "$child_line" ] \
    || fail "Parent Issue creation (line $parent_line) must precede child creation (line $child_line)"
  [ "$child_line" -lt "$checklist_line" ] \
    || fail "Child creation (line $child_line) must precede checklist update (line $checklist_line)"
}

# Scenario: 子 Issue 作成失敗時のフォールバック
# WHEN 特定リポへの子 Issue 作成が失敗する（権限不足等）
# THEN エラーを警告として表示し、残りのリポへの子 Issue 作成を継続する。
#      parent Issue のチェックリストには成功した子 Issue のみを記載する
@test "phase4-flow: SKILL.md treats child Issue creation failure as warning (non-fatal)" {
  grep -qiE '警告|warning.*continue|失敗.*継続|エラー.*警告|non.fatal|warn.*only' "$SKILL_FILE" \
    || fail "Non-fatal/warning handling for child Issue creation failure not described in SKILL.md"
}

@test "phase4-flow: SKILL.md excludes failed child Issues from checklist" {
  grep -qiE '成功.*チェックリスト|成功.*のみ.*記載|failed.*exclude|exclude.*failed|成功した.*子' "$SKILL_FILE" \
    || fail "Excluding failed child Issues from checklist not described in SKILL.md"
}

@test "phase4-flow: SKILL.md continues remaining repos after one child Issue creation fails" {
  grep -qiE '残り.*リポ.*継続|継続.*残り|continue.*remaining|remaining.*repo.*continue' "$SKILL_FILE" \
    || fail "Continuation after partial child Issue failure not described in SKILL.md"
}

# Scenario: 分割なしの場合は従来動作
# WHEN クロスリポ分割が行われていない
# THEN 既存の Phase 4 フロー（issue-create / issue-bulk-create）がそのまま使用される
@test "phase4-flow: SKILL.md uses issue-create and issue-bulk-create for non-split path" {
  grep -q 'issue-create'       "$SKILL_FILE" || fail "issue-create not referenced in SKILL.md"
  grep -q 'issue-bulk-create'  "$SKILL_FILE" || fail "issue-bulk-create not referenced in SKILL.md"
}

@test "phase4-flow: deps.yaml co-issue calls includes issue-create and issue-bulk-create" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
assert co_issue, "co-issue not found in skills section"
calls = co_issue.get('calls', [])
call_names = set()
for c in calls:
    if isinstance(c, dict):
        call_names.update(c.values())
    elif isinstance(c, str):
        call_names.add(c)
assert 'issue-create'      in call_names, f"issue-create not in co-issue calls: {call_names}"
assert 'issue-bulk-create' in call_names, f"issue-bulk-create not in co-issue calls: {call_names}"
EOF
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge: parent Issue creation must happen in current repo (not a cross-repo target)
@test "edge: SKILL.md specifies parent Issue created in current repo (not remote)" {
  grep -qiE '現在.*リポ.*parent|parent.*現在.*リポ|current.*repo.*parent' "$SKILL_FILE" \
    || fail "Parent Issue created in current repo not explicitly stated in SKILL.md"
}

# Edge: parent Issue must be specification-only (no implementation scope)
@test "edge: SKILL.md specifies parent Issue is specification-only (no implementation scope)" {
  grep -qiE '仕様.*定義.*のみ|specification.only|実装.*スコープ.*持たない|no.*implementation.*scope' "$SKILL_FILE" \
    || fail "Parent Issue specification-only constraint not described in SKILL.md"
}

# Edge: cross-repo split path must not interfere with existing Phase 4 for single-repo
@test "edge: SKILL.md Phase 4 conditionally applies cross-repo flow only when split approved" {
  # There must be a conditional branch (クロスリポ分割時 or similar guard)
  grep -qiE 'クロスリポ分割.*時|分割.*承認.*時|cross.repo.*split.*approved|if.*split\|分割時' "$SKILL_FILE" \
    || fail "Conditional guard for cross-repo Phase 4 path not found in SKILL.md"
}

# Edge: SKILL.md Phase 4 section exists
@test "edge: SKILL.md has Phase 4 section" {
  grep -q '## Phase 4' "$SKILL_FILE" \
    || fail "Phase 4 section missing from SKILL.md"
}

# Edge: checklist entries must use standard GH issue reference format (owner/repo#N)
@test "edge: SKILL.md checklist format uses owner/repo#N (not just #N)" {
  # The format must include owner/repo prefix to link cross-repo issues correctly
  grep -qE 'owner/repo#\|owner.*repo.*#' "$SKILL_FILE" \
    || fail "Cross-repo checklist format owner/repo#N not specified in SKILL.md"
}

# Edge: child Issue body Parent reference must use full owner/repo#N (not bare #N)
@test "edge: SKILL.md child Issue Parent reference uses full owner/repo#N format" {
  grep -qE 'Parent:.*owner/repo#\|Parent:.*owner.*repo.*#' "$SKILL_FILE" \
    || fail "Child Issue Parent reference must use full owner/repo#N format in SKILL.md"
}

# Edge: co-issue SKILL.md must not hardcode repo names for child Issue targets
@test "edge: SKILL.md child Issue creation loop is dynamic (no hardcoded target repos)" {
  # Look for loop-like constructs: FOR/each/各 targeting repos
  grep -qiE 'FOR.*repo\|each.*repo\|各.*リポ.*loop\|ループ.*リポ\|for each.*target' "$SKILL_FILE" \
    || fail "Dynamic loop over target repos for child Issue creation not described in SKILL.md"
}
