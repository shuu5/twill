#!/usr/bin/env bats
# EXP-006: mailbox atomic write verification (Inv T)
#
# Phase 1 PoC seed status: RED + static
#   - atomic-mail-send.sh は未実装 (Phase 1 PoC 実装段階で作成)
#   - 本 bats は registry.yaml の mailbox entity 定義の static check (3 件) + RED test 1 件
#   - GREEN 化は Phase 1 PoC 実装後 (atomic-mail-send.sh + flock + JSON Lines)
#
# 参照仕様:
#   - plugins/twl/refs/ref-invariants.md 不変条件 T (mailbox atomic)
#   - plugins/twl/registry.yaml §1 glossary.mailbox

load '../common'

setup() {
    exp_common_setup
    REGISTRY_FILE="${REPO_ROOT}/plugins/twl/registry.yaml"
    export REGISTRY_FILE
    ATOMIC_MAIL_SEND="${REPO_ROOT}/plugins/twl/scripts/atomic-mail-send.sh"
    export ATOMIC_MAIL_SEND
}

teardown() {
    exp_common_teardown
}

# ===========================================================================
# Static check: registry.yaml の mailbox entity 定義検証 (Phase 1 PoC で GREEN)
# ===========================================================================

@test "mailbox-flock-atomic: registry.yaml glossary に mailbox entity が定義されている" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
mailbox = data.get('glossary', {}).get('mailbox')
assert mailbox is not None, 'mailbox entity not in glossary'
sys.exit(0)
"
}

@test "mailbox-flock-atomic: mailbox.forbidden に 'events' / '.supervisor/events/' が含まれる (旧形式廃止)" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
mailbox = data.get('glossary', {}).get('mailbox', {})
forbidden = mailbox.get('forbidden', [])
required = {'events', '.supervisor/events/'}
missing = required - set(forbidden)
if missing:
    print('missing forbidden:', missing); sys.exit(1)
sys.exit(0)
"
}

@test "mailbox-flock-atomic: components に atomic-mail-send 関連 component は未登録 (Phase 1 PoC seed: 未実装の確認)" {
    python3 -c "
import yaml, sys
with open('$REGISTRY_FILE') as f:
    data = yaml.safe_load(f)
components = data.get('components', [])
names = {c.get('name') for c in components if isinstance(c, dict)}
# Phase 1 PoC では seed 5 件のみ (administrator + phaser-explore/refine/impl/pr)
# atomic-mail-send は Phase 2 dual-stack で components に追加予定
mailbox_components = {n for n in names if n and 'mail' in n.lower()}
# 現状は空のはず (Phase 1 seed scope)
assert not mailbox_components, f'unexpected mailbox-related components in Phase 1 seed: {mailbox_components}'
sys.exit(0)
"
}

# ===========================================================================
# RED test: atomic-mail-send.sh 未実装 (Phase 1 PoC 実装段階で GREEN 化)
# ===========================================================================

@test "mailbox-flock-atomic: atomic-mail-send.sh exists (RED until Phase 1 PoC 実装、GREEN 化シグナル)" {
    # RED 期間中はこの test が skip され、GREEN 化時に skip が外れて実 assertion が走る。
    [ -f "$ATOMIC_MAIL_SEND" ] || skip "Phase 1 PoC seed: atomic-mail-send.sh 未実装、Inv T verification は実装後 GREEN 化"
    [ -x "$ATOMIC_MAIL_SEND" ]
}
