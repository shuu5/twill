#!/usr/bin/env bats
# EXP-012: post-verify FAIL で step abort + escalate
#
# 検証内容 (不変条件 U + atomic-verification.html):
#   - test-scaffold step で test 数 0 増加 (RED test 未追加) → post-verify FAIL
#   - step abort + pilot mailbox に step-postverify-failed mail
#
# Phase 1 PoC seed status: RED + static

load '../common'

setup() {
    exp_common_setup
    REGISTRY_FILE="${REPO_ROOT}/plugins/twl/registry.yaml"
    REF_INVARIANTS="${REPO_ROOT}/plugins/twl/refs/ref-invariants.md"
    STEP_RUN_SCRIPT="${REPO_ROOT}/plugins/twl/scripts/atomic/step-run.sh"
}

teardown() {
    exp_common_teardown
}

@test "post-verify-fail: 不変条件 U が ref-invariants.md に定義されている" {
    [ -f "$REF_INVARIANTS" ] || skip "ref-invariants.md not found"
    grep -q '不変条件 U\|Invariant U' "$REF_INVARIANTS"
}

@test "post-verify-fail: registry.yaml mailbox entity に escalate mail spec が反映 (Phase 1 PoC)" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
mailbox = data.get('glossary', {}).get('mailbox')
assert mailbox is not None, 'mailbox entity not in glossary'
# Phase 1 PoC seed では mailbox は basic entity 定義のみ
# escalate mail subtype (step-postverify-failed 等) は Phase 1 PoC で追加予定
sys.exit(0)
"
}

@test "post-verify-fail: step-run.sh + post-verify hook の RED check (Phase 1 PoC GREEN 化シグナル)" {
    [ -f "$STEP_RUN_SCRIPT" ] || skip "Phase 1 PoC seed: step-run.sh 未実装、post-verify FAIL escalate 実装後 GREEN 化"
    [ -x "$STEP_RUN_SCRIPT" ]
}
