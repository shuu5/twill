#!/usr/bin/env bash
# =============================================================================
# Static Analysis: gh body+comments policy (Issue #499)
# Verifies all content-reading gh calls use gh_read_issue_full / gh_read_pr_full
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }

# ---------------------------------------------------------------------------
# Helper: grep for raw body-only reads, excluding known meta-only files
# ---------------------------------------------------------------------------
count_raw_body_reads() {
  local path="$1"
  # Match: gh issue view ... --json body (without comments) used for content
  # Exclude meta-only patterns: --json state, --json labels, --json number, etc.
  grep -rP 'gh issue view[^|]*--json body(?!,comments)' "$path" \
    --include="*.sh" --include="*.md" \
    --exclude-dir=".git" \
    --exclude-dir="deltaspec" \
    --exclude-dir="tests" \
    -l 2>/dev/null || true
}

echo "=== gh body+comments policy static analysis ==="
echo ""

# ---------------------------------------------------------------------------
# Test 1: gh-read-content.sh が存在する
# ---------------------------------------------------------------------------
echo "Test 1: scripts/lib/gh-read-content.sh の存在確認"
if [[ -f "${PROJECT_ROOT}/scripts/lib/gh-read-content.sh" ]]; then
  pass "gh-read-content.sh が存在する"
else
  fail "gh-read-content.sh が見つからない: ${PROJECT_ROOT}/scripts/lib/gh-read-content.sh"
fi

# ---------------------------------------------------------------------------
# Test 2: gh_read_issue_full 関数が定義されている
# ---------------------------------------------------------------------------
echo "Test 2: gh_read_issue_full 関数の定義確認"
if grep -q 'gh_read_issue_full()' "${PROJECT_ROOT}/scripts/lib/gh-read-content.sh" 2>/dev/null; then
  pass "gh_read_issue_full 関数が定義されている"
else
  fail "gh_read_issue_full 関数が見つからない"
fi

# ---------------------------------------------------------------------------
# Test 3: gh_read_pr_full 関数が定義されている
# ---------------------------------------------------------------------------
echo "Test 3: gh_read_pr_full 関数の定義確認"
if grep -q 'gh_read_pr_full()' "${PROJECT_ROOT}/scripts/lib/gh-read-content.sh" 2>/dev/null; then
  pass "gh_read_pr_full 関数が定義されている"
else
  fail "gh_read_pr_full 関数が見つからない"
fi

# ---------------------------------------------------------------------------
# Test 4: ac-checklist-gen.sh が gh_read_issue_full を使用している
# ---------------------------------------------------------------------------
echo "Test 4: ac-checklist-gen.sh が gh_read_issue_full を使用"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/scripts/ac-checklist-gen.sh" 2>/dev/null; then
  pass "ac-checklist-gen.sh が gh_read_issue_full を使用している"
else
  fail "ac-checklist-gen.sh がまだ --json body のみを使用している"
fi

# ---------------------------------------------------------------------------
# Test 5: chain-runner.sh の retroactive 検出箇所が gh_read_issue_full を使用している
# ---------------------------------------------------------------------------
echo "Test 5: chain-runner.sh retroactive 検出が gh_read_issue_full を使用"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/scripts/chain-runner.sh" 2>/dev/null; then
  pass "chain-runner.sh が gh_read_issue_full を使用している"
else
  fail "chain-runner.sh がまだ --json body のみを使用している"
fi

# ---------------------------------------------------------------------------
# Test 6: pr-link-issue.sh が gh_read_pr_full を使用している
# ---------------------------------------------------------------------------
echo "Test 6: pr-link-issue.sh が gh_read_pr_full を使用"
if grep -q 'gh_read_pr_full' "${PROJECT_ROOT}/scripts/pr-link-issue.sh" 2>/dev/null; then
  pass "pr-link-issue.sh が gh_read_pr_full を使用している"
else
  fail "pr-link-issue.sh がまだ --json body のみを使用している"
fi

# ---------------------------------------------------------------------------
# Test 7: worker-issue-pr-alignment.md が gh_read_issue_full を参照している
# ---------------------------------------------------------------------------
echo "Test 7: worker-issue-pr-alignment.md が gh_read_issue_full を参照"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/agents/worker-issue-pr-alignment.md" 2>/dev/null; then
  pass "worker-issue-pr-alignment.md が gh_read_issue_full を参照している"
else
  fail "worker-issue-pr-alignment.md が body のみ参照のまま"
fi

# ---------------------------------------------------------------------------
# Test 8: autopilot-multi-source-verdict.md の切り詰めが撤廃されている
# ---------------------------------------------------------------------------
echo "Test 8: autopilot-multi-source-verdict.md の切り詰め撤廃確認"
if ! grep -qE '\[:1024\]|\[-5:\]' "${PROJECT_ROOT}/commands/autopilot-multi-source-verdict.md" 2>/dev/null; then
  pass "autopilot-multi-source-verdict.md から切り詰めが撤廃されている"
else
  fail "autopilot-multi-source-verdict.md にまだ切り詰め ([:1024] or [-5:]) が残っている"
fi

# ---------------------------------------------------------------------------
# Test 9: autopilot-plan.sh が gh_read_issue_full を使用している
# ---------------------------------------------------------------------------
echo "Test 9: autopilot-plan.sh が gh_read_issue_full を使用"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/scripts/autopilot-plan.sh" 2>/dev/null; then
  pass "autopilot-plan.sh が gh_read_issue_full を使用している"
else
  fail "autopilot-plan.sh がまだ個別実装を使用している"
fi

# ---------------------------------------------------------------------------
# Test 10: workflow-issue-lifecycle SKILL.md が gh_read_issue_full を参照している
# (旧 workflow-issue-refine は v2 cutover #493 で削除済み)
# ---------------------------------------------------------------------------
echo "Test 10: workflow-issue-lifecycle SKILL.md が gh_read_issue_full を参照"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/skills/workflow-issue-lifecycle/SKILL.md" 2>/dev/null; then
  pass "workflow-issue-lifecycle SKILL.md が gh_read_issue_full を参照している"
else
  fail "workflow-issue-lifecycle SKILL.md が gh_read_issue_full を参照していない"
fi

# ---------------------------------------------------------------------------
# Test 11: co-issue SKILL.md が gh_read_issue_full を参照している
# ---------------------------------------------------------------------------
echo "Test 11: co-issue SKILL.md が gh_read_issue_full を���照"
if grep -q 'gh_read_issue_full' "${PROJECT_ROOT}/skills/co-issue/SKILL.md" 2>/dev/null; then
  pass "co-issue SKILL.md が gh_read_issue_full を参照している"
else
  fail "co-issue SKILL.md が gh_read_issue_full を���照していない"
fi

# ---------------------------------------------------------------------------
# Test 12: ref-gh-read-policy.md が存在する
# ---------------------------------------------------------------------------
echo "Test 12: refs/ref-gh-read-policy.md の存在確認"
if [[ -f "${PROJECT_ROOT}/refs/ref-gh-read-policy.md" ]]; then
  pass "ref-gh-read-policy.md が存在する"
else
  fail "ref-gh-read-policy.md が見つからない"
fi

# ---------------------------------------------------------------------------
# Test 13: issue-mgmt.md に IM-8 が追記されている
# ---------------------------------------------------------------------------
echo "Test 13: issue-mgmt.md に IM-8 が追記されている"
if grep -q 'IM-8' "${PROJECT_ROOT}/architecture/domain/contexts/issue-mgmt.md" 2>/dev/null; then
  pass "issue-mgmt.md に IM-8 が存在する"
else
  fail "issue-mgmt.md に IM-8 が見つからない"
fi

# ---------------------------------------------------------------------------
# 結果サマリー
# ---------------------------------------------------------------------------
echo ""
echo "=== 結果 ==="
echo "PASS: ${PASS}"
echo "FAIL: ${FAIL}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "=== 失敗一覧 ==="
  for err in "${ERRORS[@]}"; do
    echo "  ${err}"
  done
fi

if [[ $FAIL -eq 0 ]]; then
  echo ""
  echo "✓ 全テスト PASS — content-reading ポリシー適用済み"
  exit 0
else
  echo ""
  echo "✗ ${FAIL} テスト失敗"
  exit 1
fi
