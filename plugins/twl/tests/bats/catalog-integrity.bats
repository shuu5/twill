#!/usr/bin/env bats
# catalog-integrity.bats - Catalog reference file integrity validation
#
# Tests for Issue #842: catalog 整合性 bats テスト
#   (observation-pattern-catalog / intervention-catalog / pitfalls-catalog /
#    monitor-channel-catalog / ref-invariants 等)
#
# Coverage:
#   1. File existence — all refs in deps.yaml exist on disk
#   2. deps.yaml registration — specific catalog keys present
#   3. Section number continuity (## N. format)
#   4. MUST / MUST NOT contradiction detection (W1-3 §3.5/§10 pattern)
#   5. Internal §N cross-reference validation

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SCRIPT="${REPO_ROOT}/scripts/check-catalog-integrity.sh"
  DEPS="${REPO_ROOT}/deps.yaml"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# Group 1: File existence — all deps.yaml refs exist on disk
# ===========================================================================

@test "catalog-integrity: check-catalog-integrity.sh exists and is executable" {
  [ -f "${SCRIPT}" ]
  [ -x "${SCRIPT}" ]
}

@test "catalog-integrity: --check-existence passes for all current refs" {
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-existence
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"existence: all"*"reference files present"* ]]
}

@test "catalog-integrity: --check-existence detects missing file" {
  local fake_deps="${TMPDIR_TEST}/fake-deps.yaml"
  cat > "${fake_deps}" <<'EOF'
refs:
  nonexistent-catalog:
    type: reference
    path: refs/nonexistent-catalog.md
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --deps "${fake_deps}" --check-existence
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL: missing reference file"* ]]
}

# ===========================================================================
# Group 2: deps.yaml registration — specific catalog keys present
# ===========================================================================

@test "catalog-integrity: observation-pattern-catalog registered in deps.yaml" {
  run python3 - "${DEPS}" <<'EOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
assert 'observation-pattern-catalog' in refs, "observation-pattern-catalog not in refs"
val = refs['observation-pattern-catalog']
assert val.get('type') == 'reference', "type != reference"
assert 'path' in val, "no path"
EOF
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: intervention-catalog registered in deps.yaml" {
  run python3 - "${DEPS}" <<'EOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
assert 'intervention-catalog' in refs, "intervention-catalog not in refs"
EOF
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: pitfalls-catalog registered in deps.yaml" {
  run python3 - "${DEPS}" <<'EOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
assert 'pitfalls-catalog' in refs, "pitfalls-catalog not in refs"
EOF
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: monitor-channel-catalog registered in deps.yaml" {
  run python3 - "${DEPS}" <<'EOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
assert 'monitor-channel-catalog' in refs, "monitor-channel-catalog not in refs"
EOF
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: ref-invariants registered in deps.yaml" {
  run python3 - "${DEPS}" <<'EOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
assert 'ref-invariants' in refs, "ref-invariants not in refs"
EOF
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: all catalog files referenced in deps.yaml exist on disk" {
  run python3 - "${DEPS}" "${REPO_ROOT}" <<'EOF'
import sys, yaml, os

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
repo_root = sys.argv[2]

catalogs = [
    'observation-pattern-catalog', 'intervention-catalog',
    'pitfalls-catalog', 'monitor-channel-catalog', 'ref-invariants',
    'test-scenario-catalog',
]
missing = []
refs = data.get('refs', {})
for name in catalogs:
    if name not in refs:
        missing.append(f"not in deps.yaml: {name}")
        continue
    path = refs[name].get('path', '')
    full = os.path.join(repo_root, path)
    if not os.path.isfile(full):
        missing.append(f"file missing: {path}")

if missing:
    print('\n'.join(missing))
    sys.exit(1)
EOF
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# Group 3: Section number continuity (## N. format)
# ===========================================================================

@test "catalog-integrity: pitfalls-catalog has 14 consecutive sections §0-13" {
  local pitfalls="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  [ -f "${pitfalls}" ]
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-sections "${pitfalls}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"sections:"*"pitfalls-catalog.md"*"14 sections §0-13"* ]]
}

@test "catalog-integrity: --check-sections passes for all current ref files" {
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-sections
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: --check-sections detects missing section gap" {
  local fixture="${TMPDIR_TEST}/gap-fixture.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 1. First Section
content

## 3. Third Section (gap: §2 missing)
content
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-sections "${fixture}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"section gap"* ]]
}

@test "catalog-integrity: --check-sections passes for file without numbered sections" {
  local fixture="${TMPDIR_TEST}/no-sections.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## Overview
Some content without numbered sections

## Details
More content
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-sections "${fixture}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# Group 4: MUST / MUST NOT contradiction detection (W1-3 §3.5/§10 pattern)
# ===========================================================================

@test "catalog-integrity: --check-must passes for all current catalog files" {
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-must
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: --check-must passes for pitfalls-catalog (§3.5/§10 consistent)" {
  local pitfalls="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  [ -f "${pitfalls}" ]
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-must "${pitfalls}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no contradictions"* ]]
}

@test "catalog-integrity: --check-must detects MUST vs MUST NOT contradiction (W1-3 §3.5/§10 pattern)" {
  local fixture="${TMPDIR_TEST}/contradiction-fixture.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 3. spawn context rules
| 3.5 | spawn prompt insufficient | MUST include spawn context in prompt |

## 10. spawn prompt minimization
| MUST NOT include spawn context in prompt |
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-must "${fixture}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"MUST contradiction"* ]]
  [[ "${output}" == *"MUST 'include'"*"MUST NOT 'include'"* ]]
}

@test "catalog-integrity: --check-must does not flag one-sided MUST without MUST NOT" {
  local fixture="${TMPDIR_TEST}/one-sided-must.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 1. Rules
MUST include context in spawn prompt
MUST validate input before use
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-must "${fixture}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no contradictions"* ]]
}

@test "catalog-integrity: --check-must does not flag one-sided MUST NOT without MUST" {
  local fixture="${TMPDIR_TEST}/one-sided-must-not.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 1. Rules
MUST NOT include auto-fetchable data in prompt
MUST NOT skip validation
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-must "${fixture}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no contradictions"* ]]
}

# ===========================================================================
# Group 5: Internal §N cross-reference validation
# ===========================================================================

@test "catalog-integrity: --check-xref passes for all current ref files" {
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-xref
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: --check-xref passes for pitfalls-catalog (§3.5 refs §10, §10 exists)" {
  local pitfalls="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  [ -f "${pitfalls}" ]
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --check-xref "${pitfalls}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"xref:"*"pitfalls-catalog.md"* ]]
}

@test "catalog-integrity: --check-xref detects broken §N reference" {
  local fixture="${TMPDIR_TEST}/broken-xref.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 1. First Section
See §99 for details (but §99 does not exist)

## 2. Second Section
Normal content
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-xref "${fixture}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Broken xref"*"§99"* ]]
}

@test "catalog-integrity: --check-xref passes for file with valid §N references" {
  local fixture="${TMPDIR_TEST}/valid-xref.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## 1. First Section
Content here

## 2. Second Section
See §1 for more details
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-xref "${fixture}"
  [ "${status}" -eq 0 ]
}

@test "catalog-integrity: --check-xref skips files without numbered sections" {
  local fixture="${TMPDIR_TEST}/no-numbered.md"
  cat > "${fixture}" <<'EOF'
---
type: reference
---
## Overview
References §10 but no ##N. sections defined so check is skipped
EOF
  run bash "${SCRIPT}" --repo-root "${TMPDIR_TEST}" --check-xref "${fixture}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# Group 6: Full --all check passes
# ===========================================================================

@test "catalog-integrity: --all passes for current repo state" {
  run bash "${SCRIPT}" --repo-root "${REPO_ROOT}" --all
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PASS: catalog integrity checks passed"* ]]
}
