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

    # Phase 1 PoC Cluster 3 fix (2026-05-15): pyyaml resolve for bats invoke
    # uv run --extra test bats 経由起動時、uv 管理 python3 (3.11.15、pyyaml なし) が PATH 最優先で
    # resolve される (/home/shuu5/.local/share/uv/python/...)。system python3 (/usr/bin/python3、
    # pyyaml 6.0.1 install 済) を確実に使うため function override で pinpoint。
    # 結果: bats EXP-006/011/012/013/032/034/038 等 24 件 fail → PASS。
    if ! python3 -c "import yaml" 2>/dev/null; then
        if [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c "import yaml" 2>/dev/null; then
            python3() { /usr/bin/python3 "$@"; }
            export -f python3
        else
            echo "FATAL: no python3 with yaml module available (tried: PATH default + /usr/bin/python3)" >&2
            return 1
        fi
    fi

    SANDBOX="$(mktemp -d)"
    export EXP_DIR TEST_FIXTURES_DIR REPO_ROOT SANDBOX
}

exp_common_teardown() {
    if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
}
