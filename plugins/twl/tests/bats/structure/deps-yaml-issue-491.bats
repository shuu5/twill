#!/usr/bin/env bats
# deps-yaml-issue-491.bats - structural validation for issue-491 deps.yaml changes
#
# Spec: deltaspec/changes/issue-491/specs/deps-yaml-updates/spec.md
#
# Scenarios covered:
#   - issue-structure spawnable_by に workflow が含まれる
#   - issue-spec-review spawnable_by に workflow が含まれる
#   - issue-review-aggregate spawnable_by に workflow が含まれる
#   - issue-arch-drift spawnable_by に workflow が含まれる
#   - issue-create spawnable_by に workflow が含まれる
#   - twl check PASS (型制約違反なし)
#   - workflow-issue-lifecycle エントリの追加
#   - issue-lifecycle-orchestrator エントリの追加
#
# Edge cases:
#   - spawnable_by 拡張後も controller が残っている
#   - workflow-issue-lifecycle の can_spawn に composite/atomic/specialist が含まれる
#   - issue-lifecycle-orchestrator が scripts セクションに存在する
#   - deps.yaml が有効な YAML である

load '../helpers/common'

setup() {
  common_setup
  DEPS_FILE="$REPO_ROOT/deps.yaml"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: deps.yaml spawnable_by 拡張
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: issue-structure spawnable_by
# WHEN deps.yaml の issue-structure エントリを確認する
# THEN spawnable_by に workflow が含まれる
# ---------------------------------------------------------------------------

@test "deps-yaml-491: issue-structure spawnable_by に workflow が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

# Search all sections for issue-structure
found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-structure' in section:
        found = section['issue-structure']
        break

assert found is not None, "issue-structure not found in deps.yaml"
spawnable_by = found.get('spawnable_by', [])
assert 'workflow' in spawnable_by, \
    f"'workflow' not in issue-structure.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: issue-structure spawnable_by に controller が残っている (後方互換)" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-structure' in section:
        found = section['issue-structure']
        break

assert found is not None, "issue-structure not found"
spawnable_by = found.get('spawnable_by', [])
assert 'controller' in spawnable_by, \
    f"'controller' not in issue-structure.spawnable_by after extension: {spawnable_by}"
EOF
}

@test "deps-yaml-491: issue-spec-review spawnable_by に workflow が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-spec-review' in section:
        found = section['issue-spec-review']
        break

assert found is not None, "issue-spec-review not found in deps.yaml"
spawnable_by = found.get('spawnable_by', [])
assert 'workflow' in spawnable_by, \
    f"'workflow' not in issue-spec-review.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: issue-review-aggregate spawnable_by に workflow が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-review-aggregate' in section:
        found = section['issue-review-aggregate']
        break

assert found is not None, "issue-review-aggregate not found in deps.yaml"
spawnable_by = found.get('spawnable_by', [])
assert 'workflow' in spawnable_by, \
    f"'workflow' not in issue-review-aggregate.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: issue-arch-drift spawnable_by に workflow が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-arch-drift' in section:
        found = section['issue-arch-drift']
        break

assert found is not None, "issue-arch-drift not found in deps.yaml"
spawnable_by = found.get('spawnable_by', [])
assert 'workflow' in spawnable_by, \
    f"'workflow' not in issue-arch-drift.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: issue-create spawnable_by に workflow が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'issue-create' in section:
        found = section['issue-create']
        break

assert found is not None, "issue-create not found in deps.yaml"
spawnable_by = found.get('spawnable_by', [])
assert 'workflow' in spawnable_by, \
    f"'workflow' not in issue-create.spawnable_by: {spawnable_by}"
EOF
}

# ---------------------------------------------------------------------------
# Scenario: twl check PASS
# WHEN spawnable_by 拡張後に twl check を実行する
# THEN 型制約違反なしで PASS する
# ---------------------------------------------------------------------------

@test "deps-yaml-491: twl check が PASS する (Missing: 0)" {
  local output exit_code
  output=$(cd "$REPO_ROOT" && twl check 2>&1) || exit_code=$?
  exit_code="${exit_code:-0}"
  [ "$exit_code" -eq 0 ] \
    || fail "twl check failed (exit=$exit_code). Output: $output"
  echo "$output" | grep -qi 'Missing: 0' \
    || fail "twl check reports missing files. Output: $output"
}

@test "deps-yaml-491: twl validate が PASS する (型制約違反なし)" {
  local output exit_code
  output=$(cd "$REPO_ROOT" && twl validate 2>&1) || exit_code=$?
  exit_code="${exit_code:-0}"
  [ "$exit_code" -eq 0 ] \
    || fail "twl validate failed (exit=$exit_code). Output: $output"
  echo "$output" | grep -qi 'Violations: 0' \
    || fail "twl validate reports violations. Output: $output"
}

# ===========================================================================
# Requirement: deps.yaml 新エントリ追加
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: workflow-issue-lifecycle エントリ
# WHEN deps.yaml を確認する
# THEN workflow-issue-lifecycle エントリが type: workflow,
#      spawnable_by: [controller, user], can_spawn: [composite, atomic, specialist] を含む
# ---------------------------------------------------------------------------

@test "deps-yaml-491: workflow-issue-lifecycle エントリが deps.yaml に存在する" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found in any section of deps.yaml"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle の type が workflow である" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
t = found.get('type')
assert t == 'workflow', f"expected type=workflow, got {t}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle spawnable_by に controller が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
spawnable_by = found.get('spawnable_by', [])
assert 'controller' in spawnable_by, \
    f"'controller' not in workflow-issue-lifecycle.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle spawnable_by に user が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
spawnable_by = found.get('spawnable_by', [])
assert 'user' in spawnable_by, \
    f"'user' not in workflow-issue-lifecycle.spawnable_by: {spawnable_by}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle can_spawn に composite が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
can_spawn = found.get('can_spawn', [])
assert 'composite' in can_spawn, \
    f"'composite' not in workflow-issue-lifecycle.can_spawn: {can_spawn}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle can_spawn に atomic が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
can_spawn = found.get('can_spawn', [])
assert 'atomic' in can_spawn, \
    f"'atomic' not in workflow-issue-lifecycle.can_spawn: {can_spawn}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle can_spawn に specialist が含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
can_spawn = found.get('can_spawn', [])
assert 'specialist' in can_spawn, \
    f"'specialist' not in workflow-issue-lifecycle.can_spawn: {can_spawn}"
EOF
}

@test "deps-yaml-491: workflow-issue-lifecycle path が skills/workflow-issue-lifecycle/SKILL.md を指す" {
  python3 - "$DEPS_FILE" "$REPO_ROOT" <<'EOF'
import yaml, sys, os
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
repo_root = sys.argv[2]

found = None
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    section = data.get(section_name, {})
    if 'workflow-issue-lifecycle' in section:
        found = section['workflow-issue-lifecycle']
        break

assert found is not None, "workflow-issue-lifecycle not found"
path = found.get('path', '')
assert path == 'skills/workflow-issue-lifecycle/SKILL.md', \
    f"expected path=skills/workflow-issue-lifecycle/SKILL.md, got {path}"

# Also verify the file actually exists
full_path = os.path.join(repo_root, path)
assert os.path.exists(full_path), f"SKILL.md path does not exist: {full_path}"
EOF
}

# ---------------------------------------------------------------------------
# Scenario: issue-lifecycle-orchestrator エントリ
# WHEN deps.yaml を確認する
# THEN issue-lifecycle-orchestrator エントリが scripts セクションに存在する
# ---------------------------------------------------------------------------

@test "deps-yaml-491: issue-lifecycle-orchestrator エントリが deps.yaml に存在する" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['scripts', 'skills', 'commands', 'agents', 'refs']:
    section = data.get(section_name, {})
    if 'issue-lifecycle-orchestrator' in section:
        found = (section_name, section['issue-lifecycle-orchestrator'])
        break

assert found is not None, "issue-lifecycle-orchestrator not found in any section of deps.yaml"
EOF
}

@test "deps-yaml-491: issue-lifecycle-orchestrator が scripts セクションに存在する" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

scripts_section = data.get('scripts', {})
assert 'issue-lifecycle-orchestrator' in scripts_section, \
    "issue-lifecycle-orchestrator not found in 'scripts' section of deps.yaml"
EOF
}

@test "deps-yaml-491: issue-lifecycle-orchestrator の type が script である" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

found = None
for section_name in ['scripts', 'skills', 'commands', 'agents', 'refs']:
    section = data.get(section_name, {})
    if 'issue-lifecycle-orchestrator' in section:
        found = section['issue-lifecycle-orchestrator']
        break

assert found is not None, "issue-lifecycle-orchestrator not found"
t = found.get('type')
assert t == 'script', f"expected type=script, got {t}"
EOF
}

@test "deps-yaml-491: issue-lifecycle-orchestrator path が scripts/issue-lifecycle-orchestrator.sh を指す" {
  python3 - "$DEPS_FILE" "$REPO_ROOT" <<'EOF'
import yaml, sys, os
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
repo_root = sys.argv[2]

found = None
for section_name in ['scripts', 'skills', 'commands', 'agents', 'refs']:
    section = data.get(section_name, {})
    if 'issue-lifecycle-orchestrator' in section:
        found = section['issue-lifecycle-orchestrator']
        break

assert found is not None, "issue-lifecycle-orchestrator not found"
path = found.get('path', '')
assert path == 'scripts/issue-lifecycle-orchestrator.sh', \
    f"expected path=scripts/issue-lifecycle-orchestrator.sh, got {path}"

full_path = os.path.join(repo_root, path)
assert os.path.exists(full_path), \
    f"Orchestrator script path does not exist: {full_path}"
EOF
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "deps-yaml-491: deps.yaml が有効な YAML (python3 でパース可能)" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f)
    assert data is not None, "deps.yaml parsed as None"
except yaml.YAMLError as e:
    print(f"YAML parse error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

@test "deps-yaml-491: 5 コンポーネントの spawnable_by に workflow と controller が両方含まれる" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

targets = [
    'issue-structure',
    'issue-spec-review',
    'issue-review-aggregate',
    'issue-arch-drift',
    'issue-create',
]

all_comps = {}
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    for name, comp in data.get(section_name, {}).items():
        all_comps[name] = comp

errors = []
for target in targets:
    if target not in all_comps:
        errors.append(f"{target}: not found in deps.yaml")
        continue
    spawnable_by = all_comps[target].get('spawnable_by', [])
    if 'workflow' not in spawnable_by:
        errors.append(f"{target}.spawnable_by missing 'workflow': {spawnable_by}")
    if 'controller' not in spawnable_by:
        errors.append(f"{target}.spawnable_by missing 'controller': {spawnable_by}")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
EOF
}

@test "deps-yaml-491: 新旧エントリが coexist している (workflow-issue-lifecycle + issue-lifecycle-orchestrator)" {
  python3 - "$DEPS_FILE" <<'EOF'
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

all_comps = {}
for section_name in ['skills', 'commands', 'agents', 'refs', 'scripts']:
    for name in data.get(section_name, {}):
        all_comps[name] = True

assert 'workflow-issue-lifecycle' in all_comps, \
    "workflow-issue-lifecycle not found"
assert 'issue-lifecycle-orchestrator' in all_comps, \
    "issue-lifecycle-orchestrator not found"
EOF
}
