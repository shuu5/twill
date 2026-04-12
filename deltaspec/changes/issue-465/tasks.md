## 1. SKILL.md 責務分離ノート追記

- [ ] 1.1 `plugins/twl/skills/workflow-issue-refine/SKILL.md` Step 3b を特定する
- [ ] 1.2 Step 3b 冒頭に責務分離ノート（blockquote 形式）を追記する
- [ ] 1.3 ノートに以下を含める: LLM ガイダンス層と hook 自動ゲート層の責務境界、`spec-review-session-init.sh` 初期化必須の理由、hook deny 発動条件（`completed < total`）、`pre-tool-use-spec-review-gate.sh` への参照リンク

## 2. 動作確認

- [ ] 2.1 既存の Step 3b / 3c の動作ロジックが変更されていないことを確認する
- [ ] 2.2 追記内容が Issue #465 の AC を全て満たすことを確認する
