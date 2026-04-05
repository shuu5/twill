## ADDED Requirements

### Requirement: Specialist エージェントファイル作成

旧 dev plugin の 27 specialists を agents/ ディレクトリに移植しなければならない（SHALL）。各ファイルは以下の frontmatter を持つこと（MUST）:

- `name`: `dev:<specialist-name>` 形式
- `description`: 1 行説明（specialist）
- `type`: `specialist`
- `model`: `haiku` または `sonnet`（設計判断 D-2 に従う）
- `effort`: `low` または `medium`
- `maxTurns`: 15 または 20
- `tools`: specialist が使用するツール配列

#### Scenario: 品質判断系 specialist の移植
- **WHEN** worker-code-reviewer を移植する
- **THEN** agents/worker-code-reviewer.md が作成され、frontmatter に `model: sonnet` が宣言されている

#### Scenario: 構造チェック系 specialist の移植
- **WHEN** worker-structure を移植する
- **THEN** agents/worker-structure.md が作成され、frontmatter に `model: haiku` が宣言されている

#### Scenario: 全 27 specialist が移植完了
- **WHEN** 全移植が完了した
- **THEN** agents/ に 27 ファイルが存在し、全て frontmatter バリデーションを通過する

### Requirement: deps.yaml agents セクション登録

全 27 specialists を deps.yaml の agents セクションに登録しなければならない（MUST）。各エントリは以下のフィールドを含むこと（SHALL）:

- `type: specialist`
- `path`: `agents/<name>.md`
- `model`: `haiku` または `sonnet`
- `spawnable_by`: `[workflow, composite, controller]`
- `can_spawn`: `[]`
- `description`: 1 行説明

#### Scenario: deps.yaml に specialist を登録
- **WHEN** worker-security-reviewer を deps.yaml に登録する
- **THEN** agents セクションに `worker-security-reviewer` エントリが存在し、`type: specialist`, `model: sonnet`, `spawnable_by: [workflow, composite, controller]` が設定されている

#### Scenario: loom validate が通過
- **WHEN** 全 specialist の deps.yaml 登録が完了した
- **THEN** `loom validate` がエラーなしで通過する

### Requirement: Specialist プロンプト内容の移植

旧プラグインの各 specialist のプロンプト本文をほぼそのまま移植しなければならない（SHALL）。ただし以下の変更を適用すること（MUST）:

1. 出力形式セクションを共通出力スキーマ準拠に書き換え
2. severity 表記を CRITICAL/WARNING/INFO に正規化
3. ref-specialist-output-schema への参照を追加
4. ref-specialist-few-shot への参照を追加（該当する場合）

#### Scenario: プロンプト本文の保持
- **WHEN** worker-code-reviewer のプロンプトを移植する
- **THEN** レビュー観点（コード品質、バグパターン、可読性等）が旧プラグインと同一内容で保持されている

#### Scenario: Baseline 参照パスの更新
- **WHEN** baseline を参照する specialist を移植する
- **THEN** 参照パスが新プロジェクトの refs/ パスに更新されている
