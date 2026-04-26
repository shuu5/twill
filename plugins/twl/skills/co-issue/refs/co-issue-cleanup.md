## 終了時クリーンアップ（Phase 4 完了後）

co-issue 終了時（正常終了・エラー終了のいずれでも）に以下の一時ファイルをクリーンアップする:

```bash
# Phase 3 gate state file（hash 基準: CLAUDE_SESSION_ID）
SESSION_ID_CKSUM=$(printf '%s' "${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${SESSION_ID_CKSUM}.json"
rm -f "$GATE_FILE"

# spec-review session state file（hash 基準: CLAUDE_PROJECT_ROOT — spec-review-session-init.sh と同一）
SPEC_REVIEW_HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
SPEC_REVIEW_STATE_FILE="/tmp/.spec-review-session-${SPEC_REVIEW_HASH}.json"
rm -f "$SPEC_REVIEW_STATE_FILE"
```

**hash 算出基準の注記**: 2 つのファイルは異なる hash 基準を使用する。
- Phase 3 gate: `CLAUDE_SESSION_ID` ベース（co-issue セッション固有）
- spec-review session: `CLAUDE_PROJECT_ROOT` ベース（spec-review-session-init.sh L26 と同一）

この非対称は既存設計上の都合による。統一方針は #834 (deps.yaml 関係定義) で整理予定。
