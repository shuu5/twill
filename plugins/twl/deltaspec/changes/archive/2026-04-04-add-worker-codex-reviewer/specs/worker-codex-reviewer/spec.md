## ADDED Requirements

### Requirement: worker-codex-reviewer specialist agent 作成

`agents/worker-codex-reviewer.md` を specialist agent として作成しなければならない（SHALL）。agent は `codex exec --sandbox read-only` を Bash tool で実行し、その出力を specialist 共通スキーマ（status + findings[]）に変換して出力する。

#### Scenario: 正常レビュー実行
- **WHEN** codex がインストール済みで `CODEX_API_KEY` が設定されている状態で agent が起動され、`<review_target>` に Issue body が渡される
- **THEN** `codex exec --sandbox read-only` でレビューが実行され、`status: PASS/WARN/FAIL` と `findings: []` または findings 配列を specialist 共通スキーマ形式で出力する

#### Scenario: codex 未インストール時の graceful skip
- **WHEN** `command -v codex` が失敗する環境で agent が起動される
- **THEN** `status: PASS, findings: []` を即座に出力して完了し、エラーメッセージを出力しない

#### Scenario: CODEX_API_KEY 未設定時の graceful skip
- **WHEN** `CODEX_API_KEY` 環境変数が未設定の状態で agent が起動される
- **THEN** `status: PASS, findings: []` を即座に出力して完了し、エラーメッセージを出力しない

### Requirement: worker-codex-reviewer frontmatter

agent の frontmatter は以下の仕様に準拠しなければならない（SHALL）: `type: specialist`, `model: sonnet`, `tools: [Bash, Read, Glob, Grep]`, skills に `ref-issue-quality-criteria` と `ref-specialist-output-schema` を含む。

#### Scenario: frontmatter 準拠確認
- **WHEN** `agents/worker-codex-reviewer.md` の frontmatter を読み込む
- **THEN** `type: specialist`, `model: sonnet`, `tools: [Bash, Read, Glob, Grep]` が存在し、skills に ref-issue-quality-criteria と ref-specialist-output-schema が含まれる

## MODIFIED Requirements

### Requirement: co-issue Phase 3b に worker-codex-reviewer を追加

`skills/co-issue/SKILL.md` の Phase 3b specialist 並列 spawn ブロックに worker-codex-reviewer を追加しなければならない（SHALL）。既存の issue-critic / issue-feasibility と同じ prompt 形式（`<review_target>`, `<target_files>`, `<related_context>` タグ）で Agent tool により spawn する。

#### Scenario: Phase 3b 並列 spawn
- **WHEN** co-issue Phase 3b が実行される
- **THEN** issue-critic, issue-feasibility と並列で `Agent(subagent_type="twl:twl:worker-codex-reviewer", ...)` が spawn される

#### Scenario: findings テーブル統合
- **WHEN** worker-codex-reviewer が findings を返す
- **THEN** Step 3c の結果集約テーブルに worker-codex-reviewer 行が追加される（`| worker-codex-reviewer | <status> | <summary> |` 形式）

#### Scenario: codex スキップ時のブロックなし
- **WHEN** worker-codex-reviewer が graceful skip（status: PASS, findings: []）で完了する
- **THEN** Phase 3b 全体の処理が継続され、他の specialist の結果に影響しない

### Requirement: deps.yaml 更新

`deps.yaml` に worker-codex-reviewer を specialist として登録し、co-issue の calls と tools を更新しなければならない（SHALL）。

#### Scenario: deps.yaml 登録確認
- **WHEN** `loom check` を実行する
- **THEN** worker-codex-reviewer が agents セクションに登録され、co-issue.calls に specialist: worker-codex-reviewer が含まれ、PASS する
