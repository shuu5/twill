#!/usr/bin/env bats
# observation-references.bats - structural validation of co-self-improve data catalog references
#
# 9 test cases for #179 reference catalogs

setup() {
  # Resolve REPO_ROOT to plugins/twl/
  local helpers_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local bats_test_dir="$(cd "$helpers_dir/.." && pwd)"
  local tests_dir="$(cd "$bats_test_dir/.." && pwd)"
  REPO_ROOT="$(cd "$tests_dir/.." && pwd)"
  export REPO_ROOT
}

# ---------------------------------------------------------------------------
# Case 1: reference ファイル存在 + frontmatter 検証
# ---------------------------------------------------------------------------

@test "test-scenario-catalog: file exists and has type=reference frontmatter" {
  local file="$REPO_ROOT/refs/test-scenario-catalog.md"
  [ -f "$file" ]
  grep -q 'type: reference' "$file"
  grep -q 'spawnable_by:' "$file"
}

@test "observation-pattern-catalog: file exists and has type=reference frontmatter" {
  local file="$REPO_ROOT/refs/observation-pattern-catalog.md"
  [ -f "$file" ]
  grep -q 'type: reference' "$file"
  grep -q 'spawnable_by:' "$file"
}

@test "load-test-baselines: file exists and has type=reference frontmatter" {
  local file="$REPO_ROOT/refs/load-test-baselines.md"
  [ -f "$file" ]
  grep -q 'type: reference' "$file"
  grep -q 'spawnable_by:' "$file"
}

# ---------------------------------------------------------------------------
# Case 2: test-scenario-catalog シナリオ YAML フィールド完備
# ---------------------------------------------------------------------------

@test "test-scenario-catalog: smoke-001 and smoke-002 defined with all required fields" {
  local file="$REPO_ROOT/refs/test-scenario-catalog.md"

  # smoke-001 exists
  grep -q 'smoke-001:' "$file"
  # smoke-002 exists
  grep -q 'smoke-002:' "$file"

  # Check required fields exist in the file
  local required_fields=(level description issues_count expected_duration_min expected_duration_max expected_conflicts expected_pr_count observer_polling_interval issue_templates)
  for field in "${required_fields[@]}"; do
    grep -q "${field}:" "$file"
  done
}

@test "test-scenario-catalog: regression-001 and regression-002 defined" {
  local file="$REPO_ROOT/refs/test-scenario-catalog.md"

  grep -q 'regression-001:' "$file"
  grep -q 'regression-002:' "$file"

  # regression-001 has issues_count: 3
  grep -q 'issues_count: 3' "$file"
  # regression-002 has issues_count: 5
  grep -q 'issues_count: 5' "$file"
}

@test "test-scenario-catalog: load scenarios are TBD (not defined)" {
  local file="$REPO_ROOT/refs/test-scenario-catalog.md"

  # load-001 should only appear in comments/TBD, not as a real scenario definition
  # It should NOT have a "level: load" block with issue_templates
  local load_definitions
  load_definitions=$(grep -c 'level: load' "$file" || true)
  [ "$load_definitions" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Case 3: observation-pattern-catalog パターン数・regex 有効性
# ---------------------------------------------------------------------------

@test "observation-pattern-catalog: has at least 9 patterns across all categories" {
  local file="$REPO_ROOT/refs/observation-pattern-catalog.md"

  # Count error patterns (3+)
  local error_count
  error_count=$(grep -c '^error-' "$file" || true)
  [ "$error_count" -ge 3 ]

  # Count warning patterns (2+)
  local warn_count
  warn_count=$(grep -c '^warn-' "$file" || true)
  [ "$warn_count" -ge 2 ]

  # Count info patterns (2+)
  local info_count
  info_count=$(grep -c '^info-' "$file" || true)
  [ "$info_count" -ge 2 ]

  # Count historical patterns (2+)
  local hist_count
  hist_count=$(grep -c '^hist-' "$file" || true)
  [ "$hist_count" -ge 2 ]

  # Total 9+
  local total=$((error_count + warn_count + info_count + hist_count))
  [ "$total" -ge 9 ]
}

@test "observation-pattern-catalog: all regex patterns are valid for grep -E" {
  local file="$REPO_ROOT/refs/observation-pattern-catalog.md"

  # Extract regex values from the file and validate each
  local fail_count=0
  local pattern_count=0
  while IFS= read -r line; do
    # Extract pattern value (strip "  regex: " prefix and surrounding quotes)
    local pattern
    pattern=$(echo "$line" | sed "s/^  regex: '//" | sed "s/'$//" | sed 's/^  regex: "//' | sed 's/"$//')

    # Skip empty
    [ -z "$pattern" ] && continue
    pattern_count=$((pattern_count + 1))

    # Test if regex is valid: exit 0=match, 1=no match (both valid), 2=invalid regex
    local exit_code=0
    echo "test" | grep -E "$pattern" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
      echo "Invalid regex: $pattern" >&2
      fail_count=$((fail_count + 1))
    fi
  done < <(grep "^  regex: " "$file")

  # Ensure we actually checked some patterns
  [ "$pattern_count" -gt 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "observation-pattern-catalog: historical patterns reference #166 and #167" {
  local file="$REPO_ROOT/refs/observation-pattern-catalog.md"

  grep -q 'related_issue: "166"' "$file"
  grep -q 'related_issue: "167"' "$file"
}

# ---------------------------------------------------------------------------
# Case 4: load-test-baselines 構造検証
# ---------------------------------------------------------------------------

@test "load-test-baselines: has smoke/regression/load level table rows" {
  local file="$REPO_ROOT/refs/load-test-baselines.md"

  # Check table has all 3 levels
  grep -q '| smoke |' "$file"
  grep -q '| regression |' "$file"
  grep -q '| load |' "$file"
}

@test "load-test-baselines: smoke pass criteria mentions 5 minutes" {
  local file="$REPO_ROOT/refs/load-test-baselines.md"

  grep -q '5 分以内' "$file"
}

@test "load-test-baselines: regression pass criteria mentions 30 minutes" {
  local file="$REPO_ROOT/refs/load-test-baselines.md"

  grep -q '30 分以内' "$file"
}
