#!/usr/bin/env bats
# issue-1573-adr029-su4-wave-concurrency.bats
#
# Issue #1573: ADR-029 L165 の Wave 並走数記述が SU-4 ≤10 緩和後も旧値「5 並列まで」のまま

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "${this_dir}/../.." && pwd)"
  ADR029="${REPO_ROOT}/architecture/decisions/ADR-029-twl-mcp-integration-strategy.md"
}

@test "ADR-029: Wave 並走数が旧値「5 並列まで」を含まない" {
  run grep -n "5 並列まで" "$ADR029"
  [ "$status" -ne 0 ]
}

@test "ADR-029: Wave 並走数が SU-4 上限 10 の記述を含む" {
  run grep -n "Wave 並走数は SU-4（上限 10）を満たす" "$ADR029"
  [ "$status" -eq 0 ]
}
