## Why

`workflow-issue-refine/SKILL.md` Step 3b の記述が LLM ガイダンス層と hook 自動ゲート層の責務分離を文書化していないため、新規 reader が「完了保証は LLM の責務」と誤解するリスクがある。

## What Changes

- `plugins/twl/skills/workflow-issue-refine/SKILL.md` Step 3b 冒頭に「責務分離ノート」を追記

## Capabilities

### New Capabilities

なし（文書化のみ）

### Modified Capabilities

- `workflow-issue-refine/SKILL.md` Step 3b に責務分離ノートを追加し、以下を明記:
  - LLM ガイダンス層（spawn 手順・同期バリア）と hook 自動ゲート層（pre-tool-use-spec-review-gate.sh）の責務境界
  - `spec-review-session-init.sh` の初期化が必須である理由
  - hook による deny 発動条件（`completed < total`）
  - `pre-tool-use-spec-review-gate.sh` への参照リンク

## Impact

- **影響ファイル**: `plugins/twl/skills/workflow-issue-refine/SKILL.md`
- **動作変更なし**: 既存の Step 3b / 3c のロジックは変更しない
- **依存なし**: スクリプト・hook の変更不要
