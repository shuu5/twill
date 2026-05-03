#!/usr/bin/env bats
# smoke-ac5-dir-clarification-1230.bats
# Issue #1230: tech-debt: AC5 smoke テストと Issue body の「空 dir」定義を明確化
#
# Issue #1218 AC5 は「空 dir で起動して exit 0 確認」と記述しているが、
# smoke テストは「done 済み subdir 1 件 → exit 0」かつ「truly 空 → exit 1」を検証する。
# 「空 dir」の定義が曖昧なため、smoke テストのコメントに明示的な定義が必要。
#
# AC1:
#   issue-lifecycle-orchestrator-smoke.bats のコメントに
#   Issue #1218 AC5「空 dir」の定義（done 済み subdir を含む dir であること）が記載されている
#
# RED → GREEN 条件:
#   smoke bats に「空 dir」（Issue body・AC5 由来の表記）を使った定義コメントが追加されること

load '../../bats/helpers/common'

SMOKE_BATS=""

setup() {
    common_setup
    SMOKE_BATS="$REPO_ROOT/tests/bats/scripts/issue-lifecycle-orchestrator-smoke.bats"
}

# ---------------------------------------------------------------------------
# AC1: smoke テストに「空 dir」の定義コメントがある（Issue #1218 AC5 との対応明示）
# RED:  現状は「空ディレクトリ」（日本語）のみで「空 dir」表記がない
#       → Issue #1218 AC5 が言う「空 dir」と smoke テストのテストケースの対応が不明確
# GREEN: smoke bats に「空 dir」を使った定義コメントが追加され
#        「done 済み subdir 含む dir = exit 0」「truly 空 dir = exit 1」の区別が明示された時
# ---------------------------------------------------------------------------
@test "AC1: smoke テストに「空 dir」の定義コメントがある（Issue #1218 AC5 との対応明示）" {
    # RED: 「空 dir」（スペース含む Issue body 表記）が存在しない → 定義コメント未追加
    [ -f "$SMOKE_BATS" ]
    grep -qE "空 dir" "$SMOKE_BATS"
}
