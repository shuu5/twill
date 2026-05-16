#!/usr/bin/env bats
# tool-architect-deployment.bats - tool-architect 7-phase 全 file 配置統合検証 (8 test cases、C7)
# R-11 (agent 配置) + R-13 (Phase F opus 固定) の cross-file integration test

load '../helpers/common'

setup() {
  common_setup
  AGENTS_DIR="$REPO_ROOT/agents"
  SKILL_MD="$REPO_ROOT/skills/tool-architect/SKILL.md"
  RULES_MD="$REPO_ROOT/skills/tool-architect/refs/spec-management-rules.md"
  REGISTRY="$REPO_ROOT/registry.yaml"
}

teardown() {
  common_teardown
}

@test "all 5 specialist-spec-* agent files exist" {
  [ -f "$AGENTS_DIR/specialist-spec-explorer.md" ]
  [ -f "$AGENTS_DIR/specialist-spec-architect.md" ]
  [ -f "$AGENTS_DIR/specialist-spec-review-vocabulary.md" ]
  [ -f "$AGENTS_DIR/specialist-spec-review-structure.md" ]
  [ -f "$AGENTS_DIR/specialist-spec-review-ssot.md" ]
}

@test "SKILL.md allowed-tools includes Agent (for invoking 5 specialists)" {
  FRONTMATTER="$(sed -n '/^---$/,/^---$/p' "$SKILL_MD")"
  echo "$FRONTMATTER" | grep -qE 'Agent'
}

@test "spec-management-rules.md path referenced in SKILL.md (relative)" {
  grep -qE 'refs/spec-management-rules\.md' "$SKILL_MD"
}

@test "5 specialist-spec-* entries in registry.yaml components" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
spec_specialists = [n for n in names if n.startswith('specialist-spec-')]
assert len(spec_specialists) == 5, f'expected 5, got {spec_specialists}'
"
}

@test "each specialist-spec- registry entry name matches agent file basename" {
  python3 -c "
import yaml, os
data = yaml.safe_load(open('$REGISTRY'))
agents_dir = '$AGENTS_DIR'
for c in data.get('components', []):
    if c.get('name', '').startswith('specialist-spec-'):
        agent_file = os.path.join(agents_dir, f\"{c['name']}.md\")
        assert os.path.isfile(agent_file), f'file missing: {agent_file}'
"
}

@test "R-11 R-12 R-13 all present in spec-management-rules.md" {
  grep -qE '^## R-11:' "$RULES_MD"
  grep -qE '^## R-12:' "$RULES_MD"
  grep -qE '^## R-13:' "$RULES_MD"
}

@test "3 review agents (vocabulary/structure/ssot) all have model=opus (R-13)" {
  for axis in vocabulary structure ssot; do
    AGENT="$AGENTS_DIR/specialist-spec-review-$axis.md"
    FRONTMATTER="$(extract_frontmatter "$AGENT")"
    echo "$FRONTMATTER" | grep -qE '^model:\s*opus'
  done
}

@test "explorer and architect agents have model=sonnet (not opus)" {
  for name in explorer architect; do
    AGENT="$AGENTS_DIR/specialist-spec-$name.md"
    FRONTMATTER="$(extract_frontmatter "$AGENT")"
    echo "$FRONTMATTER" | grep -qE '^model:\s*sonnet'
  done
}
