#!/usr/bin/env bats
# co-issue-phase3-specialist.bats
#
# Structural tests for OpenSpec: co-issue-phase3-specialist-review
#
# What is tested here (all BATS-verifiable, file-/deps-level):
#   - deps.yaml: new entries (issue-critic, issue-feasibility, ref-issue-quality-criteria)
#   - deps.yaml: removed entries (issue-dig, issue-assess)
#   - deps.yaml: co-issue calls updated (specialist added, old removed)
#   - deps.yaml: co-issue can_spawn includes specialist
#   - File existence: agents/issue-critic.md, agents/issue-feasibility.md
#   - File existence: refs/ref-issue-quality-criteria.md
#   - File removal: commands/issue-dig.md, commands/issue-assess.md must NOT exist
#   - loom check passes (no missing files)
#   - loom validate passes (no type violations)
#
# What is NOT tested here:
#   - co-issue SKILL.md runtime behaviour (LLM behaviour, not structurally verifiable)
#   - Parallel spawn logic, CRITICAL-blocking flow (runtime, not testable with BATS)

load '../helpers/common'

setup() {
  common_setup
  DEPS_FILE="$REPO_ROOT/deps.yaml"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: deps.yaml に新コンポーネントを登録
# Spec: specs/deps-update.md
# ---------------------------------------------------------------------------

# Scenario: issue-critic が deps.yaml に登録されていること
@test "deps-update: issue-critic entry exists in deps.yaml" {
  grep -q '^  issue-critic:' "$DEPS_FILE"
}

@test "deps-update: issue-critic has type specialist" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
agents = data.get('agents', {})
skills = data.get('skills', {})
commands = data.get('commands', {})
# search all sections for issue-critic
found = None
for section in [agents, skills, commands]:
    if 'issue-critic' in section:
        found = section['issue-critic']
        break
assert found is not None, "issue-critic not found in deps.yaml"
assert found.get('type') == 'specialist', f"expected type=specialist, got {found.get('type')}"
EOF
}

@test "deps-update: issue-critic path points to agents/issue-critic.md" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for section in [data.get('agents', {}), data.get('skills', {}), data.get('commands', {})]:
    if 'issue-critic' in section:
        path = section['issue-critic'].get('path', '')
        assert path == 'agents/issue-critic.md', f"expected agents/issue-critic.md, got {path}"
        sys.exit(0)
sys.exit(1)
EOF
}

# Scenario: issue-feasibility が deps.yaml に登録されていること
@test "deps-update: issue-feasibility entry exists in deps.yaml" {
  grep -q '^  issue-feasibility:' "$DEPS_FILE"
}

@test "deps-update: issue-feasibility has type specialist" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
found = None
for section in [data.get('agents', {}), data.get('skills', {}), data.get('commands', {})]:
    if 'issue-feasibility' in section:
        found = section['issue-feasibility']
        break
assert found is not None, "issue-feasibility not found in deps.yaml"
assert found.get('type') == 'specialist', f"expected type=specialist, got {found.get('type')}"
EOF
}

@test "deps-update: issue-feasibility path points to agents/issue-feasibility.md" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for section in [data.get('agents', {}), data.get('skills', {}), data.get('commands', {})]:
    if 'issue-feasibility' in section:
        path = section['issue-feasibility'].get('path', '')
        assert path == 'agents/issue-feasibility.md', f"expected agents/issue-feasibility.md, got {path}"
        sys.exit(0)
sys.exit(1)
EOF
}

# Scenario: ref-issue-quality-criteria が deps.yaml に登録されていること
@test "deps-update: ref-issue-quality-criteria entry exists in deps.yaml" {
  grep -q '^  ref-issue-quality-criteria:' "$DEPS_FILE"
}

@test "deps-update: ref-issue-quality-criteria has type reference" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
found = None
for section in [data.get('refs', {}), data.get('agents', {}), data.get('skills', {}), data.get('commands', {})]:
    if 'ref-issue-quality-criteria' in section:
        found = section['ref-issue-quality-criteria']
        break
assert found is not None, "ref-issue-quality-criteria not found in deps.yaml"
assert found.get('type') == 'reference', f"expected type=reference, got {found.get('type')}"
EOF
}

@test "deps-update: ref-issue-quality-criteria path points to refs/ref-issue-quality-criteria.md" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for section in [data.get('refs', {}), data.get('agents', {}), data.get('skills', {}), data.get('commands', {})]:
    if 'ref-issue-quality-criteria' in section:
        path = section['ref-issue-quality-criteria'].get('path', '')
        assert path == 'refs/ref-issue-quality-criteria.md', f"expected refs/ref-issue-quality-criteria.md, got {path}"
        sys.exit(0)
sys.exit(1)
EOF
}

# ---------------------------------------------------------------------------
# Requirement: co-issue calls 更新
# Spec: specs/deps-update.md
# ---------------------------------------------------------------------------

# Scenario: co-issue calls に specialist: issue-critic が含まれること
@test "deps-update: co-issue calls includes specialist issue-critic" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
assert co_issue, "co-issue not found in skills section"
calls = co_issue.get('calls', [])
found = any(
    isinstance(c, dict) and c.get('specialist') == 'issue-critic'
    for c in calls
)
assert found, f"specialist: issue-critic not found in co-issue calls. calls={calls}"
EOF
}

# Scenario: co-issue calls に specialist: issue-feasibility が含まれること
@test "deps-update: co-issue calls includes specialist issue-feasibility" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
calls = co_issue.get('calls', [])
found = any(
    isinstance(c, dict) and c.get('specialist') == 'issue-feasibility'
    for c in calls
)
assert found, f"specialist: issue-feasibility not found in co-issue calls. calls={calls}"
EOF
}

# Scenario: co-issue calls に reference: ref-issue-quality-criteria が含まれること
@test "deps-update: co-issue calls includes reference ref-issue-quality-criteria" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
calls = co_issue.get('calls', [])
found = any(
    isinstance(c, dict) and c.get('reference') == 'ref-issue-quality-criteria'
    for c in calls
)
assert found, f"reference: ref-issue-quality-criteria not found in co-issue calls. calls={calls}"
EOF
}

# Scenario: co-issue can_spawn に specialist が含まれること
@test "deps-update: co-issue can_spawn includes specialist" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
can_spawn = co_issue.get('can_spawn', [])
assert 'specialist' in can_spawn, f"specialist not in co-issue can_spawn: {can_spawn}"
EOF
}

# ---------------------------------------------------------------------------
# Requirement: issue-dig 廃止
# Spec: specs/co-issue-phase3-redesign.md
# ---------------------------------------------------------------------------

# Scenario: issue-dig が deps.yaml から削除されていること
@test "phase3-redesign: issue-dig entry does NOT exist in deps.yaml" {
  if grep -q '^  issue-dig:' "$DEPS_FILE"; then
    fail "issue-dig entry still exists in deps.yaml (should be removed)"
  fi
}

# Scenario: co-issue calls に issue-dig が含まれないこと
@test "phase3-redesign: co-issue calls does NOT reference issue-dig" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
calls = co_issue.get('calls', [])
for c in calls:
    if isinstance(c, dict):
        for v in c.values():
            assert v != 'issue-dig', f"issue-dig still referenced in co-issue calls: {c}"
    elif isinstance(c, str):
        assert c != 'issue-dig', f"issue-dig still referenced in co-issue calls: {c}"
EOF
}

# Scenario: commands/issue-dig.md が削除されていること
@test "phase3-redesign: commands/issue-dig.md does NOT exist" {
  if [[ -f "$REPO_ROOT/commands/issue-dig.md" ]]; then
    fail "commands/issue-dig.md still exists (should be deleted)"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: issue-assess 廃止
# Spec: specs/co-issue-phase3-redesign.md
# ---------------------------------------------------------------------------

# Scenario: issue-assess が deps.yaml から削除されていること
@test "phase3-redesign: issue-assess entry does NOT exist in deps.yaml" {
  if grep -q '^  issue-assess:' "$DEPS_FILE"; then
    fail "issue-assess entry still exists in deps.yaml (should be removed)"
  fi
}

# Scenario: co-issue calls に issue-assess が含まれないこと
@test "phase3-redesign: co-issue calls does NOT reference issue-assess" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
calls = co_issue.get('calls', [])
for c in calls:
    if isinstance(c, dict):
        for v in c.values():
            assert v != 'issue-assess', f"issue-assess still referenced in co-issue calls: {c}"
    elif isinstance(c, str):
        assert c != 'issue-assess', f"issue-assess still referenced in co-issue calls: {c}"
EOF
}

# Scenario: commands/issue-assess.md が削除されていること
@test "phase3-redesign: commands/issue-assess.md does NOT exist" {
  if [[ -f "$REPO_ROOT/commands/issue-assess.md" ]]; then
    fail "commands/issue-assess.md still exists (should be deleted)"
  fi
}

# ---------------------------------------------------------------------------
# Requirement: issue-critic agent 作成
# Spec: specs/issue-critic-agent.md
# ---------------------------------------------------------------------------

# Scenario: agents/issue-critic.md が存在すること
@test "issue-critic-agent: agents/issue-critic.md exists" {
  [[ -f "$REPO_ROOT/agents/issue-critic.md" ]] || fail "agents/issue-critic.md not found"
}

# Scenario: issue-critic.md に model: sonnet frontmatter があること
@test "issue-critic-agent: agents/issue-critic.md has model: sonnet in frontmatter" {
  grep -q 'model:.*sonnet' "$REPO_ROOT/agents/issue-critic.md" \
    || fail "model: sonnet not found in agents/issue-critic.md"
}

# Scenario: issue-critic.md に maxTurns: 15 frontmatter があること
@test "issue-critic-agent: agents/issue-critic.md has maxTurns: 15 in frontmatter" {
  grep -q 'maxTurns:.*15' "$REPO_ROOT/agents/issue-critic.md" \
    || fail "maxTurns: 15 not found in agents/issue-critic.md"
}

# Scenario: issue-critic.md が findings 形式（category フィールド）に言及すること
@test "issue-critic-agent: agents/issue-critic.md mentions findings categories (assumption/ambiguity/scope)" {
  local file="$REPO_ROOT/agents/issue-critic.md"
  grep -qi 'assumption\|ambiguity\|scope' "$file" \
    || fail "Expected findings categories (assumption/ambiguity/scope) not found in agents/issue-critic.md"
}

# ---------------------------------------------------------------------------
# Requirement: issue-feasibility agent 作成
# Spec: specs/issue-feasibility-agent.md
# ---------------------------------------------------------------------------

# Scenario: agents/issue-feasibility.md が存在すること
@test "issue-feasibility-agent: agents/issue-feasibility.md exists" {
  [[ -f "$REPO_ROOT/agents/issue-feasibility.md" ]] || fail "agents/issue-feasibility.md not found"
}

# Scenario: issue-feasibility.md に model: sonnet frontmatter があること
@test "issue-feasibility-agent: agents/issue-feasibility.md has model: sonnet in frontmatter" {
  grep -q 'model:.*sonnet' "$REPO_ROOT/agents/issue-feasibility.md" \
    || fail "model: sonnet not found in agents/issue-feasibility.md"
}

# Scenario: issue-feasibility.md に maxTurns: 15 frontmatter があること
@test "issue-feasibility-agent: agents/issue-feasibility.md has maxTurns: 15 in frontmatter" {
  grep -q 'maxTurns:.*15' "$REPO_ROOT/agents/issue-feasibility.md" \
    || fail "maxTurns: 15 not found in agents/issue-feasibility.md"
}

# Scenario: issue-feasibility.md が feasibility category に言及すること
@test "issue-feasibility-agent: agents/issue-feasibility.md mentions feasibility category" {
  grep -qi 'feasibility' "$REPO_ROOT/agents/issue-feasibility.md" \
    || fail "feasibility category not found in agents/issue-feasibility.md"
}

# ---------------------------------------------------------------------------
# Requirement: Issue 品質基準リファレンス作成
# Spec: specs/ref-issue-quality-criteria.md
# ---------------------------------------------------------------------------

# Scenario: refs/ref-issue-quality-criteria.md が存在すること
@test "ref-issue-quality-criteria: refs/ref-issue-quality-criteria.md exists" {
  [[ -f "$REPO_ROOT/refs/ref-issue-quality-criteria.md" ]] \
    || fail "refs/ref-issue-quality-criteria.md not found"
}

# Scenario: ref が CRITICAL / WARNING / INFO の severity 基準を含むこと
@test "ref-issue-quality-criteria: mentions severity levels CRITICAL, WARNING, INFO" {
  local file="$REPO_ROOT/refs/ref-issue-quality-criteria.md"
  grep -qi 'CRITICAL' "$file" || fail "CRITICAL not found in ref-issue-quality-criteria.md"
  grep -qi 'WARNING'  "$file" || fail "WARNING not found in ref-issue-quality-criteria.md"
  grep -qi 'INFO'     "$file" || fail "INFO not found in ref-issue-quality-criteria.md"
}

# Scenario: ref が過剰 CRITICAL 防止の注意書きを含むこと
# (CRITICAL は重大問題のみ、WARNING は軽微な曖昧さに使う)
@test "ref-issue-quality-criteria: mentions CRITICAL use restriction (not overuse)" {
  local file="$REPO_ROOT/refs/ref-issue-quality-criteria.md"
  # The ref must discourage overuse of CRITICAL: look for keywords that indicate
  # restricted CRITICAL use (block/ブロック, phase 4, or scope/スコープ)
  grep -qiE 'block|ブロック|phase.?4|scope|スコープ' "$file" \
    || fail "No CRITICAL restriction guidance found in ref-issue-quality-criteria.md"
}

# ---------------------------------------------------------------------------
# Requirement: loom check / loom validate が PASS すること
# Spec: specs/deps-update.md
# ---------------------------------------------------------------------------

# Scenario: loom check が PASS すること（全ファイルが存在する）
@test "deps-update: loom check passes with no missing files" {
  local output exit_code
  output=$(cd "$REPO_ROOT" && loom check 2>&1)
  exit_code=$?
  [[ $exit_code -eq 0 ]] \
    || fail "loom check failed (exit=$exit_code). Output: $output"
  echo "$output" | grep -qi 'Missing: 0' \
    || fail "loom check reports missing files. Output: $output"
}

# Scenario: loom validate が PASS すること（型制約違反なし）
@test "deps-update: loom validate passes with no type violations" {
  local output exit_code
  output=$(cd "$REPO_ROOT" && loom validate 2>&1)
  exit_code=$?
  [[ $exit_code -eq 0 ]] \
    || fail "loom validate failed (exit=$exit_code). Output: $output"
  echo "$output" | grep -qi 'Violations: 0' \
    || fail "loom validate reports violations. Output: $output"
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

# Scenario: issue-critic と issue-feasibility の両エントリが単一 deps.yaml に共存すること
@test "edge: both issue-critic and issue-feasibility coexist in deps.yaml" {
  grep -q '^  issue-critic:'     "$DEPS_FILE" || fail "issue-critic missing"
  grep -q '^  issue-feasibility:' "$DEPS_FILE" || fail "issue-feasibility missing"
}

# Scenario: co-issue の calls から issue-dig と issue-assess が完全に消えていること
# (atomic/composite どちらの形式でも残らない)
@test "edge: co-issue calls has no reference to issue-dig or issue-assess in any form" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
co_issue = data.get('skills', {}).get('co-issue', {})
calls = co_issue.get('calls', [])
for c in calls:
    vals = list(c.values()) if isinstance(c, dict) else [c]
    for v in vals:
        assert 'issue-dig'    not in str(v), f"issue-dig still in co-issue calls: {c}"
        assert 'issue-assess' not in str(v), f"issue-assess still in co-issue calls: {c}"
EOF
}

# Scenario: co-issue の calls 参照が全て解決できること（co-issue スコープのみ）
@test "edge: co-issue calls references all resolve to existing components" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

# collect all component names across all sections
all_names = set()
for section in ['skills', 'commands', 'refs', 'scripts', 'agents']:
    for name in data.get(section, {}):
        all_names.add(name)

# check only co-issue calls references
co_issue = data.get('skills', {}).get('co-issue', {})
assert co_issue, "co-issue not found in skills"
errors = []
for call in co_issue.get('calls', []):
    if isinstance(call, dict):
        for ctype, ref in call.items():
            if ref not in all_names:
                errors.append(f"co-issue.calls: {ctype}:{ref} not found in deps.yaml")
    elif isinstance(call, str) and call not in all_names:
        errors.append(f"co-issue.calls: {call} not found in deps.yaml")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
EOF
}
