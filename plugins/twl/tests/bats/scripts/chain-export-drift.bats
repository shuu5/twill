#!/usr/bin/env bats
# chain-export-drift.bats - chain.py 編集後 export 未実行の drift 再発防止テスト (#870)
#
# Coverage (ADR-022 chain SSoT 境界):
#   1. chain.py drift: CHAIN_STEPS に step 追加 → chain-steps.sh mismatch で errors 報告
#   2. baseline: main HEAD の sandbox コピーで errors=0 (回帰防止)
#   3. deps.yaml drift: chain.py CHAIN_STEPS ∩ STEP_TO_WORKFLOW の step を全 chain から
#      削除 → "missing chain.py SSoT step" errors 報告 (ADR-022 flatten check)

load '../helpers/common'

setup() {
    common_setup

    # sandbox に plugin 構造を mirror (deps.yaml + chain-steps.sh + chain.py)
    mkdir -p "$SANDBOX/cli/twl/src/twl/autopilot"
    mkdir -p "$SANDBOX/cli/twl/src/twl/chain"

    local _git_root
    _git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

    cp "$_git_root/cli/twl/src/twl/autopilot/chain.py" \
       "$SANDBOX/cli/twl/src/twl/autopilot/chain.py"
    cp "$_git_root/cli/twl/src/twl/chain/integrity.py" \
       "$SANDBOX/cli/twl/src/twl/chain/integrity.py"
    cp "$REPO_ROOT/deps.yaml" "$SANDBOX/deps.yaml"
    cp "$REPO_ROOT/scripts/chain-steps.sh" "$SANDBOX/scripts/chain-steps.sh"
}

teardown() {
    common_teardown
}

# Helper: run integrity check against sandbox, return stdout with errors list
_run_integrity() {
    PYTHONPATH="$SANDBOX/cli/twl/src" python3 -c "
from twl.chain.integrity import check_deps_integrity
from pathlib import Path
errors, warnings = check_deps_integrity(Path('$SANDBOX'))
print('ERRORS:', len(errors))
for e in errors:
    print('ERR:', e.splitlines()[0])
print('WARNS:', len(warnings))
"
}

@test "chain-export-drift: baseline sandbox copy has errors=0 (回帰防止)" {
    run _run_integrity
    assert_success
    assert_output --partial "ERRORS: 0"
}

@test "chain-export-drift: chain.py CHAIN_STEPS drift → CHAIN_STEPS mismatch 検出" {
    local chain_py="$SANDBOX/cli/twl/src/twl/autopilot/chain.py"
    # CHAIN_STEPS AST parse 結果に drift-step を追加 (chain-steps.sh には未反映)
    python3 <<PY
import re
p = "$chain_py"
content = open(p).read()
# CHAIN_STEPS 配列の ' "init",' 直後に '"drift-step",' を挿入
modified, count = re.subn(
    r'("init",\n)(\s+")',
    r'\1    "drift-step",\n\2',
    content,
    count=1,
)
assert count == 1, f"Failed to inject drift-step (count={count})"
open(p, 'w').write(modified)
PY

    run _run_integrity
    assert_success
    assert_output --partial "CHAIN_STEPS mismatch"
}

@test "chain-export-drift: deps.yaml から chain.py SSoT step 削除 → missing error" {
    local deps="$SANDBOX/deps.yaml"
    # chain.py CHAIN_STEPS ∩ STEP_TO_WORKFLOW に含まれる "init" を全 chain から削除
    python3 <<PY
import yaml
with open("$deps") as f:
    d = yaml.safe_load(f)
for chain in d.get("chains", {}).values():
    steps = chain.get("steps", []) if isinstance(chain, dict) else chain
    if "init" in steps:
        steps.remove("init")
with open("$deps", "w") as f:
    yaml.dump(d, f, default_flow_style=False, sort_keys=False)
PY

    run _run_integrity
    assert_success
    assert_output --partial "missing chain.py SSoT step"
}
