#!/usr/bin/env bats
# session-end-pitfall-append.bats

load '../helpers/common'

SCRIPT=""

setup() {
  common_setup
  SCRIPT="$REPO_ROOT/scripts/hooks/session-end-pitfall-append.sh"

  # Minimal catalog fixture with §9 section
  CATALOG="$SANDBOX/pitfalls-catalog.md"
  cat > "$CATALOG" <<'EOF'
# Observer Pitfalls Catalog

## 1. Example section

| # | Pitfall | 対策 |
|---|---------|------|
| 1.1 | example pitfall | example fix |

---

## 9. 追記ルール

- 追加は最大 200 行。超過したら ancient entries を archive へ移動

---

## 10. Other section

content here
EOF

  SUPERVISOR_DIR="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR"

  # Stub git to prevent real repo detection
  stub_command "git" 'echo ""'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# dry-run: diff generation
# ---------------------------------------------------------------------------

@test "dry-run generates pending-pitfall-append.diff" {
  run bash "$SCRIPT" \
    --dry-run \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "New pitfall found in session"

  assert_success
  assert_output --partial "dry-run"
  assert_output --partial "pending-pitfall-append.diff"

  [ -f "$SUPERVISOR_DIR/pending-pitfall-append.diff" ]
}

@test "dry-run diff contains the entry content" {
  run bash "$SCRIPT" \
    --dry-run \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "Observer missed the inject timing"

  assert_success
  [ -f "$SUPERVISOR_DIR/pending-pitfall-append.diff" ]

  DIFF_CONTENT=$(cat "$SUPERVISOR_DIR/pending-pitfall-append.diff")
  echo "$DIFF_CONTENT" | grep -q "Observer missed the inject timing"
}

@test "dry-run does not modify catalog" {
  BEFORE=$(cat "$CATALOG")

  run bash "$SCRIPT" \
    --dry-run \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "Some new pitfall"

  assert_success
  AFTER=$(cat "$CATALOG")
  [ "$BEFORE" = "$AFTER" ]
}

@test "dry-run diff includes auto-append marker" {
  run bash "$SCRIPT" \
    --dry-run \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "session-end timing pitfall"

  assert_success
  [ -f "$SUPERVISOR_DIR/pending-pitfall-append.diff" ]
  grep -q "auto-append" "$SUPERVISOR_DIR/pending-pitfall-append.diff"
}

# ---------------------------------------------------------------------------
# normal mode: catalog append
# ---------------------------------------------------------------------------

@test "normal mode appends entry to catalog" {
  run bash "$SCRIPT" \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "New pitfall from session"

  assert_success
  assert_output --partial "Appended 1 entries"
  grep -q "\[auto\] New pitfall from session" "$CATALOG"
}

@test "normal mode appends multiple entries" {
  run bash "$SCRIPT" \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "First pitfall" "Second pitfall"

  assert_success
  grep -q "\[auto\] First pitfall" "$CATALOG"
  grep -q "\[auto\] Second pitfall" "$CATALOG"
}

@test "normal mode with --hash annotates the entry" {
  run bash "$SCRIPT" \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    --hash "abc1234f" \
    -- "Hash annotated pitfall"

  assert_success
  grep -q "hash=abc1234f" "$CATALOG"
}

@test "normal mode with --session annotates the entry" {
  run bash "$SCRIPT" \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    --session "sess-xyz" \
    -- "Session annotated pitfall"

  assert_success
  grep -q "session=sess-xyz" "$CATALOG"
}

# ---------------------------------------------------------------------------
# stdin input
# ---------------------------------------------------------------------------

@test "reads entries from stdin when no positional args" {
  run bash -c "echo 'Stdin pitfall entry' | bash '$SCRIPT' --catalog '$CATALOG' --supervisor-dir '$SUPERVISOR_DIR'"

  assert_success
  grep -q "\[auto\] Stdin pitfall entry" "$CATALOG"
}

@test "dry-run reads entries from stdin" {
  run bash -c "echo 'Stdin dry-run entry' | bash '$SCRIPT' --dry-run --catalog '$CATALOG' --supervisor-dir '$SUPERVISOR_DIR'"

  assert_success
  [ -f "$SUPERVISOR_DIR/pending-pitfall-append.diff" ]
  grep -q "Stdin dry-run entry" "$SUPERVISOR_DIR/pending-pitfall-append.diff"
}

# ---------------------------------------------------------------------------
# edge cases
# ---------------------------------------------------------------------------

@test "empty input exits cleanly with no error" {
  run bash -c "echo -n | bash '$SCRIPT' --catalog '$CATALOG' --supervisor-dir '$SUPERVISOR_DIR'"

  assert_success
  assert_output --partial "No entries"
}

@test "missing catalog exits with error" {
  run bash "$SCRIPT" \
    --catalog "$SANDBOX/nonexistent.md" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "entry"

  assert_failure
  assert_output --partial "error"
}

# ---------------------------------------------------------------------------
# 200-line limit: archive trigger
# ---------------------------------------------------------------------------

@test "exceeding 200 lines triggers archive" {
  # Generate a 210-line catalog
  {
    echo "# Catalog"
    echo ""
    for i in $(seq 1 205); do
      echo "- line $i"
    done
  } > "$CATALOG"

  ARCHIVE="$(dirname "$CATALOG")/pitfalls-archive.md"
  [ ! -f "$ARCHIVE" ]

  run bash "$SCRIPT" \
    --catalog "$CATALOG" \
    --supervisor-dir "$SUPERVISOR_DIR" \
    -- "Overflow pitfall entry"

  assert_success
  [ -f "$ARCHIVE" ] || assert_output --partial "Archived"
}
