#!/usr/bin/env bats
# changes-dir-structure.bats - architecture/changes/ dir 構造静的検証 (R-17 lifecycle、C10)
# change 001-spec-purify Specialist phase 4 (b)

load '../helpers/common'

setup() {
  common_setup
  TWILL_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
  CHANGES_DIR="$TWILL_ROOT/architecture/changes"
}

teardown() {
  common_teardown
}

@test "changes/ dir exists" {
  [ -d "$CHANGES_DIR" ]
}

@test "changes/README.md exists" {
  [ -f "$CHANGES_DIR/README.md" ]
}

@test "001-spec-purify package exists" {
  [ -d "$CHANGES_DIR/001-spec-purify" ]
}

@test "001-spec-purify has proposal.md (R-17 MUST)" {
  [ -f "$CHANGES_DIR/001-spec-purify/proposal.md" ]
}

@test "001-spec-purify has design.md (R-17 MUST)" {
  [ -f "$CHANGES_DIR/001-spec-purify/design.md" ]
}

@test "001-spec-purify has tasks.md (R-17 MUST)" {
  [ -f "$CHANGES_DIR/001-spec-purify/tasks.md" ]
}

@test "001-spec-purify has spec-delta/ dir (R-17 推奨)" {
  [ -d "$CHANGES_DIR/001-spec-purify/spec-delta" ]
}

@test "naming convention NNN-slug enforced (R-17)" {
  for d in "$CHANGES_DIR"/[0-9]*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    echo "$name" | grep -qE '^[0-9]{3}-[a-z]+(-[a-z]+)*$'
  done
}
