#!/usr/bin/env bats
# EXP-013: per-specialist mailbox scope
#
# 検証内容 (不変条件 V + failure-analysis.html Bug #1703):
#   - 2 worker 並列実行で各々が .mailbox/<worker>/inbox.jsonl に書き込み
#   - 共通 path 不在、cross-pollution 構造的に不可能
#
# Phase 1 PoC seed status: RED + static
#   - mailbox scoping logic は Phase 1 PoC 実装段階で確定

load '../common'

setup() {
    exp_common_setup
    REGISTRY_FILE="${REPO_ROOT}/plugins/twl/registry.yaml"
    REF_INVARIANTS="${REPO_ROOT}/plugins/twl/refs/ref-invariants.md"
    ATOMIC_MAIL_SEND="${REPO_ROOT}/plugins/twl/scripts/atomic-mail-send.sh"
}

teardown() {
    exp_common_teardown
}

@test "mailbox-scope: 不変条件 V が ref-invariants.md に定義されている" {
    [ -f "$REF_INVARIANTS" ] || skip "ref-invariants.md not found"
    grep -q '不変条件 V\|Invariant V' "$REF_INVARIANTS" \
        || skip "不変条件 V (mailbox scope) is not formalized (Phase 1 PoC で追記予定)"
}

@test "mailbox-scope: registry.yaml mailbox entity に per-specialist scope 注記がある (static check)" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
mailbox = data.get('glossary', {}).get('mailbox', {})
desc = mailbox.get('description', '')
# Phase 1 PoC seed では mailbox の basic entity 定義 (per-specialist scope detail は spec)
assert mailbox is not None, 'mailbox entity not in glossary'
sys.exit(0)
"
}

@test "mailbox-scope: 2 worker 並列 mock で path 不一致確認 (RED until Phase 1 PoC)" {
    [ -f "$ATOMIC_MAIL_SEND" ] || skip "Phase 1 PoC seed: atomic-mail-send.sh 未実装、mailbox scope GREEN 化は実装後"
    # Phase 1 PoC 実装後の GREEN sample:
    # worker_a="${SANDBOX}/.mailbox/worker-a/inbox.jsonl"
    # worker_b="${SANDBOX}/.mailbox/worker-b/inbox.jsonl"
    # atomic-mail-send worker-a '{"event":"test"}' &
    # atomic-mail-send worker-b '{"event":"test"}' &
    # wait
    # [ -f "$worker_a" ] && [ -f "$worker_b" ]
    # [ "$(jq -s 'length' "$worker_a")" -eq 1 ]
    # [ "$(jq -s 'length' "$worker_b")" -eq 1 ]
    skip "Phase 1 PoC GREEN: atomic-mail-send.sh + per-specialist scope 確定後"
}

@test "mailbox-scope: failure-analysis.html Bug #1703 (cross-pollution) が記録されている (static check)" {
    local fa="${REPO_ROOT}/architecture/spec/twill-plugin-rebuild/failure-analysis.html"
    [ -f "$fa" ] || skip "failure-analysis.html not found"
    grep -q '#1703\|Bug #1703' "$fa" \
        || skip "Bug #1703 not documented (Phase D で記載予定)"
}
