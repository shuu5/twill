## Requirements

### Requirement: workflow-issue-refine SKILL.md Step 3b 責務分離ノート

`workflow-issue-refine/SKILL.md` Step 3b 冒頭に、LLM ガイダンス層と hook 自動ゲート層の責務境界を説明する責務分離ノートを追記しなければならない（SHALL）。ノートには以下を含む:
- LLM ガイダンス層（spawn 手順・同期バリア）と hook 自動ゲート層の責務境界
- `spec-review-session-init.sh` の初期化が必須である理由（不在時の fallthrough）
- hook による deny 発動条件（`completed < total`）
- `plugins/twl/scripts/hooks/pre-tool-use-spec-review-gate.sh` への参照リンク

#### Scenario: 新規 reader が Step 3b を読む場合

- **WHEN** 新規 reader（人間 or LLM）が `workflow-issue-refine/SKILL.md` Step 3b を読む
- **THEN** 責務分離ノートにより「完了保証は hook により機械的に強制される」ことが理解できる

#### Scenario: LLM が spec-review-session-init.sh 呼出を省略した場合

- **WHEN** LLM が誤って `spec-review-session-init.sh` の呼出を省略し `Skill(issue-review-aggregate)` を実行しようとする
- **THEN** ノートの記述から「state ファイル不在時に hook が fallthrough する」ことが読み取れ、省略のリスクを認識できる

#### Scenario: 既存の Step 3b / 3c の動作

- **WHEN** ノートを追記した後、`workflow-issue-refine` ワークフローが実行される
- **THEN** Step 3b / 3c の動作ロジックは変更されず、既存の振る舞いが維持される（SHALL）
