#!/usr/bin/env bats
# changes-dir-structure.bats - architecture/changes/ + archive/changes/ 構造静的検証 (R-17 lifecycle)
# change 001-spec-purify Specialist phase 4 (b)
#
# R-17 規律: structural change は changes/NNN-slug/ で start し、完遂後 archive/changes/YYYY-MM-DD-NNN-slug/ に移動 MUST。
# 本 test は「completed change package が archive/changes/ 配下にあること」を verify する。

load '../helpers/common'

setup() {
  common_setup
  TWILL_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
  CHANGES_DIR="$TWILL_ROOT/architecture/changes"
  ARCHIVE_CHANGES_DIR="$TWILL_ROOT/architecture/archive/changes"
  PURIFY_ARCHIVE="$ARCHIVE_CHANGES_DIR/2026-05-16-001-spec-purify"
}

teardown() {
  common_teardown
}

@test "changes/ dir exists (進行中 change 用 root)" {
  [ -d "$CHANGES_DIR" ]
}

@test "changes/README.md exists" {
  [ -f "$CHANGES_DIR/README.md" ]
}

@test "archive/changes/ dir exists (R-17 完遂 package 移動先)" {
  [ -d "$ARCHIVE_CHANGES_DIR" ]
}

@test "001-spec-purify package archived (R-17 lifecycle 完遂)" {
  [ -d "$PURIFY_ARCHIVE" ]
}

@test "001-spec-purify archive has proposal.md (R-17 MUST)" {
  [ -f "$PURIFY_ARCHIVE/proposal.md" ]
}

@test "001-spec-purify archive has design.md (R-17 MUST)" {
  [ -f "$PURIFY_ARCHIVE/design.md" ]
}

@test "001-spec-purify archive has tasks.md (R-17 MUST)" {
  [ -f "$PURIFY_ARCHIVE/tasks.md" ]
}

@test "001-spec-purify archive has spec-delta/ dir (R-17 推奨)" {
  [ -d "$PURIFY_ARCHIVE/spec-delta" ]
}

@test "naming convention NNN-slug enforced for in-progress changes (R-17)" {
  for d in "$CHANGES_DIR"/[0-9]*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    echo "$name" | grep -qE '^[0-9]{3}-[a-z]+(-[a-z]+)*$'
  done
}

@test "naming convention YYYY-MM-DD-NNN-slug enforced for archived changes (R-17)" {
  for d in "$ARCHIVE_CHANGES_DIR"/[0-9]*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    echo "$name" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}-[a-z]+(-[a-z]+)*$'
  done
}
