#!/usr/bin/env bats
# registry-audit.bats — EXP-032: registry.yaml 5 section parse + 6 field schema + integrity_rules trigger
#
# Verifies:
#   - 5 section schema 存在 (glossary / components / chains / hooks-monitors / integrity_rules)
#   - glossary entry の 6 field schema (canonical / aliases / forbidden / context / description / examples)
#   - integrity_rules 7 件以上 + Section 11/12 audit_section mapping
#   - Section 12 core 2 rule key 存在 (prefix_role_match / no_duplicate_concern)
#
# 参照仕様:
#   - architecture/spec/twill-plugin-rebuild/registry-schema.html §1 / §4 / §5
#   - plugins/twl/architecture/decisions/ADR-045-naming-policy.md

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/../.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT
  REGISTRY_FILE="${REPO_ROOT}/registry.yaml"
  export REGISTRY_FILE
}

@test "registry-audit: registry.yaml file exists" {
  [ -f "$REGISTRY_FILE" ]
}

@test "registry-audit: registry.yaml is valid YAML" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
assert data is not None, 'registry.yaml parsed as None'
sys.exit(0)
"
}

@test "registry-audit: 5 required sections exist (glossary / components / chains / hooks-monitors / integrity_rules)" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
required = ['glossary', 'components', 'chains', 'hooks-monitors', 'integrity_rules']
missing = [s for s in required if s not in data]
if missing:
    print('missing sections:', missing)
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-audit: version 4.0 + plugin twl" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
assert data.get('version') == '4.0', f'version: {data.get(\"version\")}'
assert data.get('plugin') == 'twl', f'plugin: {data.get(\"plugin\")}'
sys.exit(0)
"
}

@test "registry-audit: glossary entries have 6 field schema (canonical/aliases/forbidden/context/description/examples)" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
required_fields = {'canonical', 'aliases', 'forbidden', 'context', 'description', 'examples'}
errors = []
for entity, entry in data.get('glossary', {}).items():
    if not isinstance(entry, dict):
        errors.append(f'{entity}: not a dict')
        continue
    missing = required_fields - set(entry.keys())
    if missing:
        errors.append(f'{entity}: missing fields {missing}')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-audit: glossary aliases is list type" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
errors = []
for entity, entry in data.get('glossary', {}).items():
    if not isinstance(entry.get('aliases'), list):
        errors.append(f'{entity}: aliases is not a list ({type(entry.get(\"aliases\")).__name__})')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-audit: glossary forbidden is list type" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
errors = []
for entity, entry in data.get('glossary', {}).items():
    if not isinstance(entry.get('forbidden'), list):
        errors.append(f'{entity}: forbidden is not a list ({type(entry.get(\"forbidden\")).__name__})')
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-audit: integrity_rules has at least 7 entries" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
rules = data.get('integrity_rules', [])
assert len(rules) >= 7, f'expected >= 7 rules, got {len(rules)}'
sys.exit(0)
"
}

@test "registry-audit: Section 12 core 2 rule keys exist (prefix_role_match / no_duplicate_concern)" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
ids = {r.get('id') for r in data.get('integrity_rules', []) if isinstance(r, dict)}
required = {'prefix_role_match', 'no_duplicate_concern'}
missing = required - ids
if missing:
    print('missing core rules:', missing)
    sys.exit(1)
sys.exit(0)
"
}

@test "registry-audit: vocabulary_forbidden_use rule audit_section is 11" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
for r in data.get('integrity_rules', []):
    if isinstance(r, dict) and r.get('id') == 'vocabulary_forbidden_use':
        s = r.get('audit_section')
        assert s == 11, f'audit_section: {s}, expected 11'
        sys.exit(0)
print('vocabulary_forbidden_use rule not found')
sys.exit(1)
"
}

@test "registry-audit: integrity_rules audit_section values are in {11, 12}" {
  python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
valid_sections = {11, 12}
errors = []
for r in data.get('integrity_rules', []):
    if isinstance(r, dict):
        s = r.get('audit_section')
        if s not in valid_sections:
            errors.append(f\"{r.get('id')}: audit_section={s}\")
if errors:
    print('\n'.join(errors))
    sys.exit(1)
sys.exit(0)
"
}
