#!/usr/bin/env bats
# test_1519_mcp_frontmatter.bats
#
# Issue #1519: tech-debt(twl-mcp): co-explore/co-autopilot SKILL.md に
#              mcpServers frontmatter を追記して subagent MCP 継承を明示する
#
# 対象 AC:
#   AC-1: co-explore/SKILL.md frontmatter に mcpServers キーが存在する
#   AC-2: co-explore/SKILL.md の mcpServers に twl エントリがある
#   AC-3: co-autopilot/SKILL.md frontmatter に mcpServers キーが存在する
#   AC-4: co-autopilot/SKILL.md の mcpServers に twl エントリがある
#
# 全テストは実装前に fail (RED) する。

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../../" && pwd)"
    CO_EXPLORE_SKILL_MD="${REPO_ROOT}/plugins/twl/skills/co-explore/SKILL.md"
    CO_AUTOPILOT_SKILL_MD="${REPO_ROOT}/plugins/twl/skills/co-autopilot/SKILL.md"
}

# ===========================================================================
# AC-1: co-explore/SKILL.md frontmatter に mcpServers キーが存在する
# RED: 現状 co-explore/SKILL.md に mcpServers の記述がないため FAIL する
# ===========================================================================

@test "ac1: co-explore/SKILL.md frontmatter に mcpServers キーが存在する" {
    [[ -f "$CO_EXPLORE_SKILL_MD" ]] \
        || { echo "FAIL: co-explore SKILL.md が見つかりません: $CO_EXPLORE_SKILL_MD"; false; }

    grep -qE '^mcpServers:' "$CO_EXPLORE_SKILL_MD" \
        || { echo "FAIL: co-explore/SKILL.md frontmatter に mcpServers キーがありません"; false; }
}

# ===========================================================================
# AC-2: co-explore/SKILL.md の mcpServers に twl エントリがある
# RED: 現状 mcpServers 自体が存在しないため FAIL する
# ===========================================================================

@test "ac2: co-explore/SKILL.md の mcpServers に twl エントリがある" {
    [[ -f "$CO_EXPLORE_SKILL_MD" ]] \
        || { echo "FAIL: co-explore SKILL.md が見つかりません: $CO_EXPLORE_SKILL_MD"; false; }

    grep -qE '^  twl:' "$CO_EXPLORE_SKILL_MD" \
        || { echo "FAIL: co-explore/SKILL.md の mcpServers に twl エントリがありません"; false; }
}

# ===========================================================================
# AC-3: co-autopilot/SKILL.md frontmatter に mcpServers キーが存在する
# RED: 現状 co-autopilot/SKILL.md に mcpServers の記述がないため FAIL する
# ===========================================================================

@test "ac3: co-autopilot/SKILL.md frontmatter に mcpServers キーが存在する" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    grep -qE '^mcpServers:' "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: co-autopilot/SKILL.md frontmatter に mcpServers キーがありません"; false; }
}

# ===========================================================================
# AC-4: co-autopilot/SKILL.md の mcpServers に twl エントリがある
# RED: 現状 mcpServers 自体が存在しないため FAIL する
# ===========================================================================

@test "ac4: co-autopilot/SKILL.md の mcpServers に twl エントリがある" {
    [[ -f "$CO_AUTOPILOT_SKILL_MD" ]] \
        || { echo "FAIL: co-autopilot SKILL.md が見つかりません: $CO_AUTOPILOT_SKILL_MD"; false; }

    grep -qE '^  twl:' "$CO_AUTOPILOT_SKILL_MD" \
        || { echo "FAIL: co-autopilot/SKILL.md の mcpServers に twl エントリがありません"; false; }
}
