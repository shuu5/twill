#!/usr/bin/env bats
# tdd-green-guard.bats — Issue #1633 / ADR-039 AC4 / AC5
#
# 検証内容:
#   G1: 未知フレームワーク → exit 0 + WARNING (graceful skip)
#   G2: bats 全 PASS + impl_files diff あり → exit 0 (GREEN 確立)
#   G3: bats 1 件 fail → exit 1 (テスト未 GREEN)
#   G4: bats 全 PASS + impl_files が diff にない → exit 1 (impl 不在)
#   G5: ac-test-mapping.yaml 不在 → test 全 PASS なら exit 0 + WARNING (graceful skip)

load '../helpers/common'

GUARD_SCRIPT="scripts/tdd-green-guard.sh"
GUARD_PATH=""
REPO_DIR=""

skip_if_guard_missing() {
  [[ -f "$GUARD_PATH" ]] || skip "guard script not found: $GUARD_PATH"
}

setup() {
  common_setup
  GUARD_PATH="$REPO_ROOT/$GUARD_SCRIPT"
  REPO_DIR="$SANDBOX/repo"
  mkdir -p "$REPO_DIR"
}

teardown() {
  common_teardown
}

_init_git() {
  (
    cd "$REPO_DIR" || exit 1
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "test"
    git commit -q --allow-empty -m "base"
    git checkout -q -b feat/test
    git update-ref refs/remotes/origin/main main
  )
}

_write_mapping() {
  local impl_path="$1"
  cat > "$REPO_DIR/ac-test-mapping.yaml" <<MAP
mappings:
  - ac_index: 1
    ac_text: "test AC"
    test_file: "tests/foo.bats"
    test_name: "ac1"
    impl_files:
      - "$impl_path"
MAP
}

# ---------------------------------------------------------------------------
# G1: unknown framework → graceful skip
# ---------------------------------------------------------------------------

@test "G1: unknown framework → exit 0 + WARNING" {
  skip_if_guard_missing
  _init_git
  # No test files → unknown framework

  run bash -c "cd '$REPO_DIR' && bash '$GUARD_PATH'"

  assert_success
  echo "$output" | grep -qE "unknown.*skip" || fail "expected WARNING about unknown framework. output: $output"
}

# ---------------------------------------------------------------------------
# G2: bats 全 PASS + impl_files diff あり → exit 0
# ---------------------------------------------------------------------------

@test "G2: bats GREEN + impl_files in diff → exit 0" {
  skip_if_guard_missing
  command -v bats >/dev/null || skip "bats not installed in test env"

  _init_git
  (
    cd "$REPO_DIR" || exit 1
    mkdir -p tests src
    cat > tests/foo.bats <<'BATS'
#!/usr/bin/env bats
@test "ac1" { [[ "$(cat src/foo.sh)" == "ok" ]]; }
BATS
    echo "ok" > src/foo.sh
    git add tests/foo.bats src/foo.sh
    git commit -q -m "GREEN test+impl"
  )
  _write_mapping "src/foo.sh"

  run bash -c "cd '$REPO_DIR' && bash '$GUARD_PATH' --mapping '$REPO_DIR/ac-test-mapping.yaml'"

  [[ "$status" -eq 0 ]] || fail "expected exit 0 (GREEN). status=$status output=$output"
  echo "$output" | grep -q "GREEN guard" || fail "missing GREEN message. output: $output"
}

# ---------------------------------------------------------------------------
# G3: bats 1 件 fail → exit 1
# ---------------------------------------------------------------------------

@test "G3: bats has FAIL → exit 1" {
  skip_if_guard_missing
  command -v bats >/dev/null || skip "bats not installed in test env"

  _init_git
  (
    cd "$REPO_DIR" || exit 1
    mkdir -p tests src
    cat > tests/foo.bats <<'BATS'
#!/usr/bin/env bats
@test "ac1" { false; }
BATS
    git add tests/foo.bats
    git commit -q -m "RED only"
  )
  _write_mapping "src/foo.sh"

  run bash -c "cd '$REPO_DIR' && bash '$GUARD_PATH' --mapping '$REPO_DIR/ac-test-mapping.yaml'"

  [[ "$status" -eq 1 ]] || fail "expected exit 1 (FAIL). status=$status"
  echo "$output" | grep -q "FAIL" || fail "missing FAIL message. output: $output"
}

# ---------------------------------------------------------------------------
# G4: bats 全 PASS + impl_files が diff にない → exit 1
# ---------------------------------------------------------------------------

@test "G4: bats GREEN but impl_files NOT in diff → exit 1" {
  skip_if_guard_missing
  command -v bats >/dev/null || skip "bats not installed in test env"

  _init_git
  (
    cd "$REPO_DIR" || exit 1
    mkdir -p tests
    cat > tests/foo.bats <<'BATS'
#!/usr/bin/env bats
@test "ac1" { true; }
BATS
    git add tests/foo.bats
    git commit -q -m "test only"
  )
  # mapping は src/missing.sh を impl_files として宣言、ただし diff にない
  _write_mapping "src/missing.sh"

  run bash -c "cd '$REPO_DIR' && bash '$GUARD_PATH' --mapping '$REPO_DIR/ac-test-mapping.yaml'"

  [[ "$status" -eq 1 ]] || fail "expected exit 1 (impl_files missing). status=$status"
  echo "$output" | grep -qE "impl_files.*git diff" || fail "missing impl_files error. output: $output"
}

# ---------------------------------------------------------------------------
# G5: mapping 不在 → test 全 PASS なら exit 0 (graceful skip)
# ---------------------------------------------------------------------------

@test "G5: ac-test-mapping.yaml 不在 + bats GREEN → exit 0 + WARNING" {
  skip_if_guard_missing
  command -v bats >/dev/null || skip "bats not installed in test env"

  _init_git
  (
    cd "$REPO_DIR" || exit 1
    mkdir -p tests
    cat > tests/foo.bats <<'BATS'
#!/usr/bin/env bats
@test "ac1" { true; }
BATS
    git add tests/foo.bats
    git commit -q -m "GREEN"
  )
  # mapping ファイルは作らない

  run bash -c "cd '$REPO_DIR' && bash '$GUARD_PATH'"

  assert_success
  echo "$output" | grep -qE "ac-test-mapping.*未検出|mapping.*skip" \
    || fail "expected WARNING about missing mapping. output: $output"
}
