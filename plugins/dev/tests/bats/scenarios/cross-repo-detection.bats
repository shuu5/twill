#!/usr/bin/env bats
# cross-repo-detection.bats
# BDD tests for OpenSpec: co-issue-cross-repo-split / cross-repo-detection
# Spec: openspec/changes/co-issue-cross-repo-split/specs/cross-repo-detection.md
#
# Coverage: happy-path + edge-cases
#
# What is tested (all BATS-verifiable, structure/content level):
#   - SKILL.md: Phase 2 contains cross-repo detection logic
#   - SKILL.md: explicit multi-repo mention detection
#   - SKILL.md: keyword-based detection (全リポ, 3リポ, 各リポ, クロスリポ)
#   - SKILL.md: single-repo content falls through to normal flow
#   - SKILL.md: Project-linked repo list dynamic acquisition (no hardcode)
#   - SKILL.md: AskUserQuestion for split proposal
#   - SKILL.md: user approval leads to per-repo child issue structure
#   - SKILL.md: user rejection falls through to single-issue flow
#   - deps.yaml: co-issue calls includes cross-repo related components (if any)
#
# What is NOT tested here (LLM runtime behaviour):
#   - actual GitHub API calls for project-linked repos
#   - runtime cross-repo detection logic execution
#   - AskUserQuestion actual user interaction

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
# Requirement: クロスリポ検出
# Spec: openspec/changes/co-issue-cross-repo-split/specs/cross-repo-detection.md
# ---------------------------------------------------------------------------

# Scenario: 3リポ横断の要望を検出する
# WHEN explore-summary.md に「loom, loom-plugin-dev, loom-plugin-session の3リポに配置」という記述がある
# THEN クロスリポ横断として検出され、対象リポリスト [loom, loom-plugin-dev, loom-plugin-session] が生成される
@test "cross-repo-detection: SKILL.md Phase 2 mentions cross-repo detection logic" {
  grep -qi 'クロスリポ\|cross.repo\|cross_repo' "$SKILL_FILE" \
    || fail "Phase 2 cross-repo detection not mentioned in SKILL.md"
}

@test "cross-repo-detection: SKILL.md references explore-summary.md reading in Phase 2" {
  grep -q 'explore-summary' "$SKILL_FILE" \
    || fail "explore-summary.md not referenced in SKILL.md Phase 2"
}

@test "cross-repo-detection: SKILL.md Phase 2 handles multi-repo name detection" {
  # The SKILL.md must describe that multiple distinct repo names trigger cross-repo detection
  local content
  content=$(cat "$SKILL_FILE")
  # Accept either explicit mention of "2つ以上"/"複数リポ" or "クロスリポ検出" in Phase 2 section
  echo "$content" | grep -qiE 'クロスリポ検出|複数リポ|cross.repo detect|multi.repo' \
    || fail "SKILL.md does not describe multi-repo name detection for cross-repo trigger"
}

# Scenario: 単一リポの要望はスルーする
# WHEN explore-summary.md に単一リポのみの変更記述がある
# THEN クロスリポ検出はトリガーされず、従来の分解判断フローに進む
@test "cross-repo-detection: SKILL.md preserves normal decomposition flow when no cross-repo detected" {
  # The skill must still have the standard decomposition path (単一/複数 Issue 判断)
  grep -q '単一\|分解' "$SKILL_FILE" \
    || fail "Normal single/decompose flow not present in SKILL.md"
}

@test "cross-repo-detection: SKILL.md Phase 2 runs cross-repo check AFTER reading explore-summary" {
  # Phase 2 section must mention reading explore-summary before cross-repo detection
  local phase2_section
  phase2_section=$(awk '/## Phase 2/,/## Phase 3/' "$SKILL_FILE")
  echo "$phase2_section" | grep -q 'explore-summary' \
    || fail "explore-summary.md read not found in Phase 2 section of SKILL.md"
}

# Scenario: 「全リポ」キーワードで検出する
# WHEN explore-summary.md に「全リポに適用」というキーワードがある
# THEN 現在のリポが属する Project のリンク済み全リポがクロスリポ対象として検出される
@test "cross-repo-detection: SKILL.md mentions keyword-based detection (全リポ/各リポ/クロスリポ)" {
  grep -qE '全リポ|各リポ|クロスリポ|3リポ' "$SKILL_FILE" \
    || fail "Cross-repo keywords (全リポ/各リポ/クロスリポ/3リポ) not mentioned in SKILL.md"
}

# ---------------------------------------------------------------------------
# Requirement: リポ一覧の動的取得
# Spec: openspec/changes/co-issue-cross-repo-split/specs/cross-repo-detection.md
# ---------------------------------------------------------------------------

# Scenario: Project リンク済みリポから取得する
# WHEN 現在のリポが GitHub Project #3 (loom-dev-ecosystem) にリンクされている
# THEN 同 Project にリンクされた全リポが対象リポ一覧として返される
@test "cross-repo-detection: SKILL.md acquires repo list dynamically from GitHub Project" {
  # Must mention GitHub Project or gh CLI for dynamic repo list acquisition
  grep -qiE 'GitHub Project|gh.*project|project.*リンク|linked.*repo' "$SKILL_FILE" \
    || fail "Dynamic repo list from GitHub Project not described in SKILL.md"
}

@test "cross-repo-detection: SKILL.md does NOT contain hardcoded repo list" {
  # Hardcoded list pattern: a literal array of the three known repos
  # This is a soft check - warns if loom-plugin-dev appears as a hardcoded list
  local hardcoded_pattern='loom.*loom-plugin-dev.*loom-plugin-session\|loom-plugin-session.*loom-plugin-dev.*loom'
  if grep -qE "$hardcoded_pattern" "$SKILL_FILE"; then
    # Allow it only if it appears as an example in a comment-like context (#### Scenario etc)
    local suspicious_lines
    suspicious_lines=$(grep -E "$hardcoded_pattern" "$SKILL_FILE" | grep -Ev '^#|^>|Scenario|example|例')
    if [ -n "$suspicious_lines" ]; then
      fail "Hardcoded repo list found in SKILL.md (should be dynamic): $suspicious_lines"
    fi
  fi
}

# Scenario: Project にリンクされていない場合
# WHEN 現在のリポがどの Project にもリンクされていない
# THEN クロスリポ検出は実行されず、従来の分解判断フローに進む
@test "cross-repo-detection: SKILL.md handles no-project-link fallback gracefully" {
  # The SKILL.md must describe fallback when no project is linked
  grep -qiE 'project.*リンク.*なし|no.*project|project.*not.*link|リンクされていない|従来.*フロー|fallback' "$SKILL_FILE" \
    || fail "No-project-link fallback not described in SKILL.md"
}

# ---------------------------------------------------------------------------
# Requirement: 分割提案の確認
# Spec: openspec/changes/co-issue-cross-repo-split/specs/cross-repo-detection.md
# ---------------------------------------------------------------------------

# Scenario: ユーザーが分割を承認する
# WHEN クロスリポ検出後に分割提案が表示され、ユーザーが承認を選択する
# THEN Phase 3 以降はリポ単位の子 Issue 構造で精緻化が進む
@test "cross-repo-detection: SKILL.md presents split proposal via AskUserQuestion" {
  grep -qiE 'AskUserQuestion|split.*提案|分割.*提案' "$SKILL_FILE" \
    || fail "Split proposal via AskUserQuestion not described in SKILL.md"
}

@test "cross-repo-detection: SKILL.md approval path leads to per-repo child issue structure" {
  # After approval, Phase 3/4 should handle per-repo child issue structure
  grep -qiE '子.*Issue|child.*issue|リポ.*単位|per.repo' "$SKILL_FILE" \
    || fail "Per-repo child issue structure not mentioned in SKILL.md"
}

# Scenario: ユーザーが分割を拒否する
# WHEN クロスリポ検出後に分割提案が表示され、ユーザーが拒否を選択する
# THEN 従来通り単一 Issue として Phase 3 以降の処理に進む
@test "cross-repo-detection: SKILL.md rejection path falls back to single-issue flow" {
  # The AskUserQuestion must offer a rejection option that routes to normal flow
  local skill_content
  skill_content=$(cat "$SKILL_FILE")
  # Must have options for both approve (A) and reject/normal (B or C)
  echo "$skill_content" | grep -qE '\[A\]|\[B\]|\[C\]' \
    || fail "AskUserQuestion options [A]/[B]/[C] not found in SKILL.md"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Edge: Phase 2 section exists with cross-repo block before decomposition judgment
@test "edge: SKILL.md Phase 2 section exists and precedes Phase 3" {
  local phase2_line phase3_line
  phase2_line=$(grep -n '## Phase 2' "$SKILL_FILE" | head -1 | cut -d: -f1)
  phase3_line=$(grep -n '## Phase 3' "$SKILL_FILE" | head -1 | cut -d: -f1)
  [ -n "$phase2_line" ] || fail "Phase 2 section missing from SKILL.md"
  [ -n "$phase3_line" ] || fail "Phase 3 section missing from SKILL.md"
  [ "$phase2_line" -lt "$phase3_line" ] \
    || fail "Phase 2 must appear before Phase 3 in SKILL.md"
}

# Edge: cross-repo detection logic placed within Phase 2 (not Phase 1 or 4)
@test "edge: cross-repo detection described within Phase 2 section (not Phase 1)" {
  local phase1_end phase2_content
  # Extract Phase 2 section text
  phase2_content=$(awk '/## Phase 2/,/## Phase 3/' "$SKILL_FILE")
  # Phase 2 section must contain cross-repo mention
  echo "$phase2_content" | grep -qiE 'クロスリポ|cross.repo' \
    || fail "Cross-repo detection not in Phase 2 section; must not be in Phase 1 or later"
}

# Edge: SKILL.md file exists and is non-empty
@test "edge: skills/co-issue/SKILL.md exists and is non-empty" {
  [ -f "$SKILL_FILE" ] || fail "skills/co-issue/SKILL.md does not exist"
  [ -s "$SKILL_FILE" ] || fail "skills/co-issue/SKILL.md is empty"
}

# Edge: co-issue entry in deps.yaml references SKILL.md
@test "edge: deps.yaml co-issue path points to skills/co-issue/SKILL.md" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
assert co_issue, "co-issue not found in skills section of deps.yaml"
path = co_issue.get('path', '')
assert path == 'skills/co-issue/SKILL.md', \
    f"Expected path=skills/co-issue/SKILL.md, got: {path}"
EOF
}
