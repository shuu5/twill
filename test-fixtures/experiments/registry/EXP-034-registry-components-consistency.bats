#!/usr/bin/env bats
# EXP-034: registry.yaml ↔ 実 SKILL.md frontmatter 整合性
#
# Phase 1 PoC seed 範囲:
#   seed 5 component (administrator + phaser-explore/refine/impl/pr) のみ検証。
#   SKILL.md 不存在の場合は skip (Phase 3 cutover で旧 file rename 完了後に再検証)。
#
# 参照仕様:
#   - architecture/spec/twill-plugin-rebuild/registry-schema.html §1.5.4
#   - plugins/twl/architecture/decisions/ADR-045-naming-policy.md

load '../common'

setup() {
    exp_common_setup
    REGISTRY_FILE="${REPO_ROOT}/plugins/twl/registry.yaml"
    export REGISTRY_FILE
}

teardown() {
    exp_common_teardown
}

@test "registry-components: seed 5 component が registry.yaml components に列挙されている" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
names = {c.get('name') for c in components if isinstance(c, dict)}
seed = {'administrator', 'phaser-explore', 'phaser-refine', 'phaser-impl', 'phaser-pr'}
missing = seed - names
if missing:
    print('missing seed components:', missing)
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-components: phaser-* 4 件は role=phaser である" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
phasers = [c for c in components if isinstance(c, dict) and c.get('name', '').startswith('phaser-')]
errors = []
for c in phasers:
    if c.get('role') != 'phaser':
        errors.append(f\"{c.get('name')}: role={c.get('role')!r}, expected 'phaser'\")
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-components: administrator は role=administrator である" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
for c in components:
    if isinstance(c, dict) and c.get('name') == 'administrator':
        assert c.get('role') == 'administrator', f'role={c.get(\"role\")!r}'
        sys.exit(0)
print('administrator component not found')
sys.exit(1)
"
}

@test "registry-components: seed components は file field を持つ" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
seed = {'administrator', 'phaser-explore', 'phaser-refine', 'phaser-impl', 'phaser-pr'}
errors = []
for c in components:
    if isinstance(c, dict) and c.get('name') in seed:
        if not c.get('file'):
            errors.append(f\"{c.get('name')}: missing 'file' field\")
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-components: administrator SKILL.md 存在時 frontmatter name が一致 (Phase 3 cutover 後 GREEN)" {
    local skill_md="${REPO_ROOT}/plugins/twl/skills/administrator/SKILL.md"
    [ -f "$skill_md" ] || skip "Phase 1 PoC seed: administrator SKILL.md 未作成 (Phase 3 cutover で作成)"
    python3 -c "
import yaml, sys, re
with open('$skill_md') as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
assert m, 'frontmatter not found'
fm = yaml.safe_load(m.group(1))
name = fm.get('name', '')
short = name.split(':', 1)[-1] if ':' in name else name
assert short == 'administrator', f'SKILL.md name={short!r}'
sys.exit(0)
"
}

@test "registry-components: phaser-impl SKILL.md 存在時 frontmatter name が一致 (Phase 3 cutover 後 GREEN)" {
    local skill_md="${REPO_ROOT}/plugins/twl/skills/phaser-impl/SKILL.md"
    [ -f "$skill_md" ] || skip "Phase 1 PoC seed: phaser-impl SKILL.md 未作成 (Phase 3 cutover で作成)"
    python3 -c "
import yaml, sys, re
with open('$skill_md') as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
assert m, 'frontmatter not found'
fm = yaml.safe_load(m.group(1))
name = fm.get('name', '')
short = name.split(':', 1)[-1] if ':' in name else name
assert short == 'phaser-impl', f'SKILL.md name={short!r}'
sys.exit(0)
"
}

@test "registry-components: prefix_role_match - phaser-* component の prefix と role 一致" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
errors = []
for c in components:
    if not isinstance(c, dict):
        continue
    name = c.get('name', '')
    role = c.get('role', '')
    if name.startswith('phaser-'):
        if role != 'phaser':
            errors.append(f\"{name}: prefix 'phaser-' but role={role!r}\")
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}
