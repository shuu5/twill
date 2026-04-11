#!/usr/bin/env bats
# spec-new-auto-init-guard.bats
# Requirement: twl spec new auto-init fallback 抑制ガード（AC-1, issue #485）
# Spec: deltaspec/changes/issue-485/specs/auto-init-suppression/spec.md
#
# pre-#435 branch（nested deltaspec/config.yaml が存在しない）において
# `twl spec new` が早期失敗することを検証する。
#
# test double: git stub が origin/main に nested config.yaml を返す環境を再現。

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: sandbox に twl ラッパーと git stub を配置
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # Python source path for twl
  REPO_ROOT_REAL="$(cd "${BATS_TEST_DIR}/../../../../.." && pwd)"
  PYTHON_SRC="${REPO_ROOT_REAL}/cli/twl/src"
  export PYTHONPATH="${PYTHON_SRC}:${PYTHONPATH:-}"

  # Create a git stub that simulates origin/main with nested deltaspec/config.yaml
  cat > "$SANDBOX/git" <<'EOF'
#!/usr/bin/env bash
# git stub: simulate ls-tree returning nested deltaspec/config.yaml
if [[ "$1" == "ls-tree" ]]; then
  echo "plugins/twl/deltaspec/config.yaml"
  echo "cli/twl/deltaspec/config.yaml"
  echo "README.md"
  exit 0
fi
# Passthrough for other git commands
exec /usr/bin/git "$@"
EOF
  chmod +x "$SANDBOX/git"
  export PATH="$SANDBOX:$PATH"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "pre-#435 branch: twl spec new が nested root 検出時に早期失敗する" {
  # sandbox は deltaspec/config.yaml を持たない（pre-#435 branch 相当）
  run python3 -m twl spec new issue-test-999
  assert_failure
  assert_output --partial "nested deltaspec root"
  # deltaspec/ が作成されていないこと
  [[ ! -d "$SANDBOX/deltaspec" ]] || fail "deltaspec/ should not be created"
}

@test "pre-#435 branch: エラーメッセージに rebase hint が含まれる" {
  run python3 -m twl spec new issue-test-999
  assert_failure
  assert_output --partial "rebase"
}

@test "TWL_SPEC_ALLOW_AUTO_INIT=1 で従来の auto-init が動作する" {
  export TWL_SPEC_ALLOW_AUTO_INIT=1
  run python3 -m twl spec new issue-test-999
  assert_success
  [[ -d "deltaspec/changes/issue-test-999" ]] || fail "change dir should be created"
  unset TWL_SPEC_ALLOW_AUTO_INIT
}
