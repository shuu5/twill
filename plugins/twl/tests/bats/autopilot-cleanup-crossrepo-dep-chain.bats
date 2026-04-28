#!/usr/bin/env bats
# autopilot-cleanup-crossrepo-dep-chain.bats
#
# Issue #1011: is_in_dependency_chain が CROSS_REPO uid (lpd#42 形式) に対応していない
#
# AC1: cross-repo uid が depender の場合、依存チェーンを正しく検出してアーカイブをスキップする
#      RED: 現在の /^  [0-9]+:/ パターンは lpd#50 にマッチしない → return 1 (archive OK バグ)
#      GREEN (修正後): /^  [[:alnum:]_#-]+:/ にマッチ → return 0 (archive スキップ)
# AC2: integer depender は修正前後ともに正常動作する（regression なし）
# AC3: cross-repo uid depender が archive 済みの場合は archive を許可する

load 'helpers/common'

SCRIPT=""

# Helper: is_in_dependency_chain を sandbox 内で実行
# 実 autopilot-cleanup.sh から関数定義を抽出して subshell で呼び出す
_run_dep_chain() {
  local issue_num="$1"
  local func_def
  func_def=$(sed -n '/^is_in_dependency_chain()/,/^}/p' "$SCRIPT")

  run bash -c "
set -euo pipefail
export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
${func_def}
is_in_dependency_chain '${issue_num}'
"
}

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/autopilot-cleanup.sh"
  mkdir -p "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot/archive/session-test"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: cross-repo uid が depender の場合、依存チェーン検出が機能する
# RED: /^  [0-9]+:/ は "lpd#50" にマッチしない → dependers="" → return 1 (archive バグ)
# ===========================================================================
@test "ac1: cross-repo uid depender が pending の場合、archive をスキップする (return 0)" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
dependencies:
  lpd#50:
  - 42
EOF
  printf '{"status":"in_progress"}' > "$SANDBOX/.autopilot/issues/issue-lpd#50.json"

  _run_dep_chain "42"
  assert_success  # return 0 = archive スキップ
}

# ===========================================================================
# AC2: integer depender は修正前後ともに正常検出される（regression なし）
# ===========================================================================
@test "ac2: integer depender が pending の場合、archive をスキップする (return 0)" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
dependencies:
  50:
  - 42
EOF
  printf '{"status":"in_progress"}' > "$SANDBOX/.autopilot/issues/issue-50.json"

  _run_dep_chain "42"
  assert_success  # return 0 = archive スキップ
}

# ===========================================================================
# AC3: cross-repo uid depender が archive 済みの場合は archive を許可する
# ===========================================================================
@test "ac3: cross-repo uid depender が archive 済みの場合、archive を許可する (return 1)" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
dependencies:
  lpd#50:
  - 42
EOF
  # issues/ にはない、archive/ にある（done 扱い）
  printf '{"status":"done"}' > "$SANDBOX/.autopilot/archive/session-test/issue-lpd#50.json"

  _run_dep_chain "42"
  assert_failure  # return 1 = archive OK
}

# ===========================================================================
# AC1b: cross-repo uid が複数 depender のうち 1 つでも pending なら archive スキップ
# ===========================================================================
@test "ac1b: cross-repo uid + integer depender 混在で、pending が 1 つでもあれば archive スキップ" {
  cat > "$SANDBOX/.autopilot/plan.yaml" <<'EOF'
dependencies:
  lpd#50:
  - 42
  60:
  - 42
EOF
  # lpd#50 は pending、60 は done
  printf '{"status":"in_progress"}' > "$SANDBOX/.autopilot/issues/issue-lpd#50.json"
  printf '{"status":"done"}' > "$SANDBOX/.autopilot/archive/session-test/issue-60.json"

  _run_dep_chain "42"
  assert_success  # return 0 = archive スキップ（lpd#50 が pending）
}
