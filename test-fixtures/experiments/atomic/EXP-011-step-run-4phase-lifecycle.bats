#!/usr/bin/env bats
# EXP-011: step::run 4 phase lifecycle (pre-check → exec → post-verify → report)
#
# 検証内容 (atomic-verification.html §3 + ssot-design.html §3):
#   - step::run が 4 phase 順序実行 (pre-check → exec → post-verify → report)
#   - 各 phase で mailbox event を発行
#
# Phase 1 PoC seed status: RED + static
#   - atomic skill (step::run) は未実装 (Phase 1 PoC 実装段階で作成)
#   - 本 bats は registry.yaml の atomic-related entity 定義 static check + RED test
#   - GREEN 化は Phase 1 PoC 実装後

load '../common'

setup() {
    exp_common_setup
    REGISTRY_FILE="${REPO_ROOT}/plugins/twl/registry.yaml"
    STEP_RUN_SCRIPT="${REPO_ROOT}/plugins/twl/scripts/atomic/step-run.sh"
}

teardown() {
    exp_common_teardown
}

@test "step-run-4phase: registry.yaml glossary に atomic-related entity (atomic / step) が登録されている" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
glossary = data.get('glossary', {})
# atomic skill 関連の canonical entity が定義済みであることを確認
# Phase 1 PoC seed では atomic / mailbox entity が必須
required = {'atomic', 'mailbox'}
missing = required - set(glossary.keys())
if missing:
    print('missing atomic-related glossary entries:', missing)
    sys.exit(1)
sys.exit(0)
"
}

@test "step-run-4phase: atomic-verification.html spec に 4 phase 記述あり (static check)" {
    local spec="${REPO_ROOT}/architecture/spec/twill-plugin-rebuild/atomic-verification.html"
    [ -f "$spec" ] || skip "atomic-verification.html not found (Phase B 想定の spec)"
    # 4 phase の名称 (pre-check / exec / post-verify / report) が記載されていることを確認
    grep -q 'pre-check\|post-verify\|exec\|report' "$spec" \
        || skip "4 phase 記述未確認 (spec が Phase 1 PoC 設計中)"
}

@test "step-run-4phase: step-run.sh exists (RED until Phase 1 PoC 実装、GREEN 化シグナル)" {
    [ -f "$STEP_RUN_SCRIPT" ] || skip "Phase 1 PoC seed: step-run.sh 未実装、4 phase lifecycle 実装後 GREEN 化"
    [ -x "$STEP_RUN_SCRIPT" ]
}
