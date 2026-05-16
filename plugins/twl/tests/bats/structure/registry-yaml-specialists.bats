#!/usr/bin/env bats
# registry-yaml-specialists.bats - registry.yaml の 6 specialist-spec-* entry 検証 (change 001-spec-purify C10、R-11 enforcement、temporal 追加で 5→6)

load '../helpers/common'

setup() {
  common_setup
  REGISTRY="$REPO_ROOT/registry.yaml"
}

teardown() {
  common_teardown
}

@test "registry.yaml exists" {
  [ -f "$REGISTRY" ]
}

@test "registry.yaml is valid YAML" {
  python3 -c "import yaml; yaml.safe_load(open('$REGISTRY'))"
}

@test "registry.yaml components has specialist-spec-explorer" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-explorer' in names, names
"
}

@test "registry.yaml components has specialist-spec-architect" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-architect' in names, names
"
}

@test "registry.yaml components has specialist-spec-review-vocabulary" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-review-vocabulary' in names, names
"
}

@test "registry.yaml components has specialist-spec-review-structure" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-review-structure' in names, names
"
}

@test "registry.yaml components has specialist-spec-review-ssot" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-review-ssot' in names, names
"
}

@test "registry.yaml components has specialist-spec-review-temporal (change 001-spec-purify)" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
assert 'specialist-spec-review-temporal' in names, names
"
}

@test "registry.yaml 6 specialist-spec-* entries exist (change 001-spec-purify: temporal 追加で 5→6)" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
names = [c['name'] for c in data.get('components', [])]
spec_specialists = [n for n in names if n.startswith('specialist-spec-')]
assert len(spec_specialists) == 6, f'expected 6, got {len(spec_specialists)}: {spec_specialists}'
"
}

@test "registry.yaml glossary.specialist.examples contains 6 specialist-spec-* entries" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
examples = data.get('glossary', {}).get('specialist', {}).get('examples', [])
spec_examples = [e for e in examples if 'specialist-spec' in e]
assert len(spec_examples) >= 6, f'expected >= 6 specialist-spec-* examples, got {len(spec_examples)}: {spec_examples}'
"
}

@test "registry.yaml specialist-spec-* component names match agent file paths" {
  python3 -c "
import yaml
data = yaml.safe_load(open('$REGISTRY'))
for c in data.get('components', []):
    if c.get('name', '').startswith('specialist-spec-'):
        expected_file = f\"agents/{c['name']}.md\"
        actual_file = c.get('file', '')
        assert actual_file == expected_file, f\"name={c['name']}, file={actual_file}, expected={expected_file}\"
"
}
