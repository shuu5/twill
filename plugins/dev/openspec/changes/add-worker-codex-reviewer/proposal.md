## Why

co-issue Phase 3b の specialist レビューは同一モデルファミリー（Claude）に偏っており、異なる AI モデルの視点による多角的な Issue 品質検証ができない。既存の `scripts/codex-review.sh` は dead code 状態のため、Codex CLI を specialist agent として統合することで多角的検証を実現する。

## What Changes

- 新規 specialist agent `agents/worker-codex-reviewer.md` を作成（Bash で `codex exec` を呼び、specialist 共通スキーマで出力）
- `skills/co-issue/SKILL.md` の Phase 3b に worker-codex-reviewer の spawn を追加
- `deps.yaml` に worker-codex-reviewer を登録し、co-issue.calls / co-issue.tools を更新

## Capabilities

### New Capabilities

- **worker-codex-reviewer**: Codex CLI（OpenAI モデル）を使って Issue 品質を specialist 共通スキーマ形式でレビューする agent
- **Graceful degradation**: codex 未インストール or `CODEX_API_KEY` 未設定時は `status: PASS, findings: []` で即完了し、Phase 3b 全体をブロックしない

### Modified Capabilities

- **co-issue Phase 3b**: issue-critic・issue-feasibility と並列で worker-codex-reviewer を spawn し、Step 3c の findings テーブルに統合する

## Impact

- 追加ファイル: `agents/worker-codex-reviewer.md`
- 変更ファイル: `skills/co-issue/SKILL.md`, `deps.yaml`
- 既存の `scripts/codex-review.sh` は変更しない（dead code のまま）
- 既存 specialist（issue-critic, issue-feasibility）の動作に影響なし
