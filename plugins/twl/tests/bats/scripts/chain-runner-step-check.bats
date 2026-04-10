#!/usr/bin/env bats
# chain-runner-step-check.bats - unit tests for step_check() in chain-runner.sh
#
# Issue: #406 — step_check が monorepo-level tests/ を期待し全件 FAIL
#
# Coverage:
#   AC-1: $root/tests/, $root/*/tests/, $root/*/*/tests/ いずれかにテストがあれば PASS
#   AC-2: $root/tests/ 不在でもコンポーネント配下にテストがあれば FAIL にならない
#   AC-3: 単一リポ（$root/tests/ 存在）の退行がない

load '../helpers/common'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  stub_command "git" '
    case "$*" in
      *"branch --show-current"*)
        echo "fix/406-stepcheck-monorepo-level-tests-fail" ;;
      *"rev-parse --show-toplevel"*)
        echo "$SANDBOX" ;;
      *"rev-parse --git-dir"*)
        echo "$SANDBOX/.git" ;;
      *"status --porcelain"*)
        echo "" ;;
      *)
        exit 0 ;;
    esac
  '

  stub_command "gh" 'exit 0'

  mkdir -p "$SANDBOX/scripts/lib"
  cat > "$SANDBOX/scripts/lib/resolve-project.sh" <<'RESOLVE_PROJECT'
#!/usr/bin/env bash
resolve_project() {
  echo "6 PVT_project_id shuu5 twill-ecosystem shuu5/twill"
}
RESOLVE_PROJECT
  chmod +x "$SANDBOX/scripts/lib/resolve-project.sh"

  # .github/workflows をデフォルトで用意
  mkdir -p "$SANDBOX/.github/workflows"
  touch "$SANDBOX/.github/workflows/ci.yml"

  # deltaspec/changes/proposal.md をデフォルトで用意
  mkdir -p "$SANDBOX/deltaspec/changes/some-change"
  touch "$SANDBOX/deltaspec/changes/some-change/proposal.md"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-3: 単一リポ（$root/tests/ 存在）— 退行なし
# ---------------------------------------------------------------------------

@test "step_check: \$root/tests/ にテストがあれば Tests: PASS" {
  mkdir -p "$SANDBOX/tests"
  touch "$SANDBOX/tests/foo.bats"

  run bash "$SANDBOX/scripts/chain-runner.sh" check
  assert_output --partial "Tests: PASS"
  assert_success
}

# ---------------------------------------------------------------------------
# AC-2: monorepo — $root/tests/ 不在でもコンポーネント配下があれば PASS
# ---------------------------------------------------------------------------

@test "step_check: \$root/tests/ 不在でも \$root/plugins/twl/tests/ にテストがあれば Tests: PASS" {
  mkdir -p "$SANDBOX/plugins/twl/tests"
  touch "$SANDBOX/plugins/twl/tests/foo.bats"

  run bash "$SANDBOX/scripts/chain-runner.sh" check
  assert_output --partial "Tests: PASS"
  assert_success
}

@test "step_check: \$root/tests/ 不在でも \$root/cli/twl/tests/ にテストがあれば Tests: PASS" {
  mkdir -p "$SANDBOX/cli/twl/tests"
  touch "$SANDBOX/cli/twl/tests/test_chain.py"

  run bash "$SANDBOX/scripts/chain-runner.sh" check
  assert_output --partial "Tests: PASS"
  assert_success
}

# ---------------------------------------------------------------------------
# AC-1: $root/*/tests/ パターン（深さ1）
# ---------------------------------------------------------------------------

@test "step_check: \$root/*/tests/ 配下のテストを検出できる" {
  mkdir -p "$SANDBOX/plugins/tests"
  touch "$SANDBOX/plugins/tests/spec.sh"

  run bash "$SANDBOX/scripts/chain-runner.sh" check
  assert_output --partial "Tests: PASS"
  assert_success
}

# ---------------------------------------------------------------------------
# テストが全く存在しない場合は FAIL
# ---------------------------------------------------------------------------

@test "step_check: テストファイルが一切なければ Tests: FAIL" {
  # tests/ ディレクトリを作らない

  run bash "$SANDBOX/scripts/chain-runner.sh" check
  assert_output --partial "Tests: FAIL"
  assert_failure
}
