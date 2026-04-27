#!/usr/bin/env bats
# baseline-bash-section6.bats - Verify Issue #951: baseline-bash.md に
# ## 6. 複数 regex パターンの ^ アンカー一貫性 セクションが追加されていること

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TESTS_DIR="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
  BASELINE="${REPO_ROOT}/refs/baseline-bash.md"
  export REPO_ROOT BASELINE
}

# ===========================================================================
# AC1: ## 6. 複数 regex パターンの ^ アンカー一貫性 セクションが存在する
# ===========================================================================

@test "baseline-bash-section6: AC1 section '## 6. 複数 regex パターンの ^ アンカー一貫性' exists" {
  [ -f "${BASELINE}" ]
  grep -qF '## 6. 複数 regex パターンの ^ アンカー一貫性' "${BASELINE}"
}

# ===========================================================================
# AC2: BAD 例として Pattern 1 strict / Pattern 2 leading-space の不整合を引用
# ===========================================================================

@test "baseline-bash-section6: AC2 BAD example mentions strict Pattern1 '^[1-9]\\.' and leading-space Pattern2" {
  [ -f "${BASELINE}" ]
  # Pattern 1 strict form
  grep -qE '\^\[1-9\]\\.' "${BASELINE}"
  # Pattern 2 leading-space form
  grep -qE '\^\[\[:space:\]\]\*\[1-9\]' "${BASELINE}"
}

# ===========================================================================
# AC3: GOOD 例として 2 種（^[[:space:]]* 統一 / strict ^ 統一）が併記されている
# ===========================================================================

@test "baseline-bash-section6: AC3 GOOD example 'all patterns use ^[[:space:]]*' form is present" {
  [ -f "${BASELINE}" ]
  grep -qE '\^\[\[:space:\]\]\*' "${BASELINE}"
}

@test "baseline-bash-section6: AC3 GOOD example 'all patterns use strict ^' form is present" {
  [ -f "${BASELINE}" ]
  # Section 6 should mention both GOOD forms; check that we have two distinct GOOD code blocks
  local count
  count=$(grep -c '^# GOOD' "${BASELINE}")
  # baseline already has 9 GOOD examples in §1-5; §6 adds at least 2 more → total ≥ 11
  [ "${count}" -ge 11 ]
}

# ===========================================================================
# AC4: レビュー観点（同一 input source に対する複数 regex の ^ 直後比較）が明示
# ===========================================================================

@test "baseline-bash-section6: AC4 review observation mentions comparing ^ character class for same input source" {
  [ -f "${BASELINE}" ]
  # Either Japanese or mixed — grep for key phrase
  grep -qE '同一.*input.*source|同一.*ソース.*regex|同一.*input.*regex|same input source' "${BASELINE}"
}

# ===========================================================================
# AC5: PR #949 or commit e3d2f80 の Why 注記が記載されている
# ===========================================================================

@test "baseline-bash-section6: AC5 Why note references PR #949 or commit e3d2f80 or Issue #946" {
  [ -f "${BASELINE}" ]
  grep -qE '#949|e3d2f80|#946' "${BASELINE}"
}

# ===========================================================================
# AC6: twl check --deps-integrity が PASS する
# ===========================================================================

@test "baseline-bash-section6: AC6 twl check --deps-integrity passes" {
  run bash -c "cd '${REPO_ROOT}' && twl check --deps-integrity"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC7: worker-code-reviewer.md / worker-codex-reviewer.md は変更されていない
# (uncommitted changes がないこと = このIssue実装でagentを変更していないこと)
# ===========================================================================

@test "baseline-bash-section6: AC7 worker-code-reviewer.md has no uncommitted changes" {
  run git -C "${REPO_ROOT}" diff HEAD -- agents/worker-code-reviewer.md
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "baseline-bash-section6: AC7 worker-codex-reviewer.md has no uncommitted changes" {
  run git -C "${REPO_ROOT}" diff HEAD -- agents/worker-codex-reviewer.md
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
