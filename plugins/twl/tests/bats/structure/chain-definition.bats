#!/usr/bin/env bats
# chain-definition.bats - chain definition integrity tests

load '../helpers/common'

setup() {
  common_setup
  DEPS_FILE="$REPO_ROOT/deps.yaml"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: chain definition integrity
# ---------------------------------------------------------------------------

# Scenario: chain step reference resolution
@test "chain: all setup chain steps exist as components in deps.yaml" {
  # Extract step names from setup chain
  local steps
  steps=$(python3 -c "
import yaml, sys
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
for step in data.get('chains', {}).get('setup', {}).get('steps', []):
    if isinstance(step, str):
        print(step)
    elif isinstance(step, dict):
        for k in step:
            print(k)
")

  # Check each step exists as a component somewhere in deps.yaml
  local all_components
  all_components=$(python3 -c "
import yaml, sys
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
for section in ['skills', 'commands', 'refs', 'scripts', 'agents']:
    for name in data.get(section, {}):
        print(name)
# Also collect calls targets (atomic/composite names referenced in skills)
for section in ['skills', 'commands']:
    for comp_name, comp in data.get(section, {}).items():
        if isinstance(comp, dict):
            for call in comp.get('calls', []):
                if isinstance(call, dict):
                    for ctype in ['atomic', 'composite', 'specialist', 'reference', 'script']:
                        if ctype in call:
                            print(call[ctype])
                elif isinstance(call, str):
                    print(call)
")

  while IFS= read -r step; do
    [[ -z "$step" ]] && continue
    echo "$all_components" | grep -qxF "$step" || {
      echo "Step '$step' in setup chain not found as component"
      return 1
    }
  done <<< "$steps"
}

# Scenario: chain step reference resolution (pr-cycle)
@test "chain: all pr-cycle chain steps exist as components in deps.yaml" {
  local steps
  steps=$(python3 -c "
import yaml, sys
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
for step in data.get('chains', {}).get('pr-cycle', {}).get('steps', []):
    if isinstance(step, str):
        print(step)
    elif isinstance(step, dict):
        for k in step:
            print(k)
")

  local all_components
  all_components=$(python3 -c "
import yaml, sys
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
for section in ['skills', 'commands', 'refs', 'scripts', 'agents']:
    for name in data.get(section, {}):
        print(name)
for section in ['skills', 'commands']:
    for comp_name, comp in data.get(section, {}).items():
        if isinstance(comp, dict):
            for call in comp.get('calls', []):
                if isinstance(call, dict):
                    for ctype in ['atomic', 'composite', 'specialist', 'reference', 'script']:
                        if ctype in call:
                            print(call[ctype])
                elif isinstance(call, str):
                    print(call)
")

  while IFS= read -r step; do
    [[ -z "$step" ]] && continue
    echo "$all_components" | grep -qxF "$step" || {
      echo "Step '$step' in pr-cycle chain not found as component"
      return 1
    }
  done <<< "$steps"
}

# Scenario: chain type validity
@test "chain: all chain types are A or B" {
  local types
  types=$(python3 -c "
import yaml, sys
with open('$DEPS_FILE') as f:
    data = yaml.safe_load(f)
for name, chain in data.get('chains', {}).items():
    print(f'{name}:{chain.get(\"type\", \"MISSING\")}')
")

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local chain_name="${entry%%:*}"
    local chain_type="${entry##*:}"
    [[ "$chain_type" == "A" || "$chain_type" == "B" ]] || {
      echo "Chain '$chain_name' has invalid type '$chain_type' (expected A or B)"
      return 1
    }
  done <<< "$types"
}
