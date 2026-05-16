#!/usr/bin/env bats
# output-schema-model.bats - ref-specialist-output-schema.md update 検証 (6 test cases、C7、C1 commit)

load '../helpers/common'

setup() {
  common_setup
  SCHEMA_MD="$REPO_ROOT/refs/ref-specialist-output-schema.md"
}

teardown() {
  common_teardown
}

@test "ref-specialist-output-schema.md exists" {
  [ -f "$SCHEMA_MD" ]
}

@test "schema mentions opus for specialist use (no longer restricted to Controller/Workflow)" {
  grep -qE 'opus.*deep audit|deep audit.*opus' "$SCHEMA_MD"
}

@test "schema lists specialist-exp-reviewer as opus example" {
  grep -qE 'specialist-exp-reviewer' "$SCHEMA_MD"
}

@test "schema lists specialist-spec-review-* as opus examples" {
  grep -qE 'specialist-spec-review-vocabulary' "$SCHEMA_MD"
  grep -qE 'specialist-spec-review-structure' "$SCHEMA_MD"
  grep -qE 'specialist-spec-review-ssot' "$SCHEMA_MD"
}

@test "schema category enum includes spec-vocabulary/spec-structure/spec-ssot" {
  grep -qE 'spec-vocabulary' "$SCHEMA_MD"
  grep -qE 'spec-structure' "$SCHEMA_MD"
  grep -qE 'spec-ssot' "$SCHEMA_MD"
}

@test "schema mentions confidence >= 80 merge-gate filter" {
  grep -qE 'confidence.*80|80.*confidence' "$SCHEMA_MD"
}
