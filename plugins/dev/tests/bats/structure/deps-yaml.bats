#!/usr/bin/env bats
# deps-yaml.bats - structural validation of deps.yaml v3.0

load '../helpers/common'

setup() {
  common_setup
  DEPS_FILE="$REPO_ROOT/deps.yaml"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: deps.yaml structural validation
# ---------------------------------------------------------------------------

# Scenario: required fields exist
@test "deps-yaml: version field exists" {
  grep -q '^version:' "$DEPS_FILE"
}

@test "deps-yaml: plugin field exists" {
  grep -q '^plugin:' "$DEPS_FILE"
}

@test "deps-yaml: entry_points field exists" {
  grep -q '^entry_points:' "$DEPS_FILE"
}

# Scenario: entry_points file existence
@test "deps-yaml: all entry_points reference existing files" {
  local entry_points
  entry_points=$(grep '^ *- ' "$DEPS_FILE" | head -20 | sed -n '/entry_points/,/^[a-z]/p' | grep '^ *- ' | sed 's/^ *- *//')

  # Parse entry_points section properly
  entry_points=$(awk '/^entry_points:/{found=1; next} /^[a-z]/{found=0} found && /^ *- /{gsub(/^ *- */,""); print}' "$DEPS_FILE")

  [ -n "$entry_points" ] || skip "no entry_points found"

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ -f "$REPO_ROOT/$path" ] || fail "entry_point not found: $path"
  done <<< "$entry_points"
}

# Scenario: component path file existence
@test "deps-yaml: all component paths reference existing files" {
  local paths
  paths=$(grep '^\s\+path:' "$DEPS_FILE" | sed 's/.*path:\s*//' | tr -d '"' | tr -d "'")

  [ -n "$paths" ] || skip "no component paths found"

  while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ -f "$REPO_ROOT/$path" ] || fail "component path not found: $path"
  done <<< "$paths"
}

# Scenario: calls references resolve
@test "deps-yaml: all calls references exist as components" {
  # Extract all component names (keys under skills:, atomics:, composites:, etc.)
  local component_names
  component_names=$(awk '/^  [a-zA-Z0-9_-]+:$/ || /^  [a-zA-Z0-9_-]+: *$/{gsub(/^ +/,""); gsub(/:.*$/,""); print}' "$DEPS_FILE" | sort -u)

  # Extract all calls references
  local calls_refs
  calls_refs=$(grep '^\s\+- \(atomic\|composite\|specialist\|reference\|script\):' "$DEPS_FILE" \
    | sed 's/.*: *//' | tr -d '"' | sort -u)

  [ -n "$calls_refs" ] || skip "no calls references found"

  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if ! echo "$component_names" | grep -qxF "$ref"; then
      fail "calls reference '$ref' not found as a component in deps.yaml"
    fi
  done <<< "$calls_refs"
}

# ---------------------------------------------------------------------------
# Edge cases / structural integrity
# ---------------------------------------------------------------------------

@test "deps-yaml: version is 3.0" {
  local version
  version=$(grep '^version:' "$DEPS_FILE" | head -1 | sed 's/version:\s*//' | tr -d '"')
  [ "$version" = "3.0" ]
}

@test "deps-yaml: plugin is dev" {
  local plugin
  plugin=$(grep '^plugin:' "$DEPS_FILE" | head -1 | sed 's/plugin:\s*//' | tr -d '"')
  [ "$plugin" = "dev" ]
}

@test "deps-yaml: all component types are valid" {
  local types
  # Extract types from component sections only (exclude chain types A/B)
  types=$(python3 -c "
import yaml
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
types = set()
for section in ['skills', 'commands', 'refs', 'scripts', 'agents']:
    for name, comp in data.get(section, {}).items():
        if isinstance(comp, dict) and 'type' in comp:
            types.add(comp['type'])
for t in sorted(types):
    print(t)
")

  local valid="controller workflow composite atomic specialist reference script"
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    local found=false
    for vt in $valid; do
      [ "$t" = "$vt" ] && found=true && break
    done
    [ "$found" = "true" ] || fail "invalid type: $t"
  done <<< "$types"
}

@test "deps-yaml: exactly 4 controllers" {
  local count
  count=$(grep '^\s\+type:\s*controller' "$DEPS_FILE" | wc -l)
  [ "$count" -eq 4 ]
}

@test "deps-yaml: file is valid YAML (no tabs)" {
  # YAML does not allow tabs for indentation
  if grep -P '\t' "$DEPS_FILE"; then
    fail "deps.yaml contains tab characters"
  fi
}
