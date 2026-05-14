# Common bats helper for test-fixtures/experiments/<category>/*.bats
#
# Provides REPO_ROOT resolution and basic setup/teardown for EXP bats tests.
# Each EXP bats sources this file via `load '../common'` from category subdir.
#
# Layout expected:
#   test-fixtures/experiments/
#   ├── common.bash           ← THIS FILE
#   └── <category>/
#       └── EXP-NNN-*.bats    ← BATS_TEST_FILENAME

exp_common_setup() {
    local this_dir
    this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    EXP_DIR="$(cd "${this_dir}/.." && pwd)"
    TEST_FIXTURES_DIR="$(cd "${EXP_DIR}/.." && pwd)"
    REPO_ROOT="$(cd "${TEST_FIXTURES_DIR}/.." && pwd)"

    # Verify by marker files instead of basename so worktree checkouts
    # (e.g., worktrees/<branch>/) and renamed repo roots still work.
    if [[ ! -f "${REPO_ROOT}/plugins/twl/registry.yaml" \
       || ! -d "${REPO_ROOT}/experiments" \
       || ! -d "${REPO_ROOT}/test-fixtures/experiments" ]]; then
        echo "FATAL: REPO_ROOT resolution failed (got: $REPO_ROOT)" >&2
        return 1
    fi

    SANDBOX="$(mktemp -d)"
    export EXP_DIR TEST_FIXTURES_DIR REPO_ROOT SANDBOX
}

exp_common_teardown() {
    if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
}
