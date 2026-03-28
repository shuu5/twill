## ADDED Requirements

### Requirement: co-architect SKILL.md 対話的設計フロー実装

co-architect の SKILL.md を stub から完全実装に置き換えなければならない（MUST）。旧 controller-architect のワークフローを移植し、対話的アーキテクチャ構築を提供する。

SKILL.md は以下の Step 構成を持たなければならない（SHALL）:

- Step 0: --group モード分岐（--group 指定時は architect-group-refine を呼び出して終了）
- Step 1: コンテキスト収集（README.md, CLAUDE.md, architecture/ 読み取り）
- Step 2: 対話的探索（/dev:explore 呼び出し、architecture/ ファイルへの書き込み）
- Step 3: 完全性チェック（architect-completeness-check 呼び出し）
- Step 4: Phase 計画（phases/ への書き込み）
- Step 5: Issue 分解（architect-decompose 呼び出し）
- Step 6: 整合性チェック（6項目チェック結果表示）
- Step 7: ユーザー確認（Issue 候補の最終承認）
- Step 8: 一括 Issue 作成（architect-issue-create → project-board-sync）

#### Scenario: 通常のアーキテクチャ設計フロー
- **WHEN** ユーザーが `/dev:co-architect` を実行する
- **THEN** Step 1〜8 が順次実行され、architecture/ が構築され、Issue 候補が作成される

#### Scenario: --group モードによるスケルトン Issue 精緻化
- **WHEN** `--group <context-name>` が指定される
- **THEN** architect-group-refine が呼び出され、指定 Context のスケルトン Issue 群が一括精緻化される

### Requirement: TaskCreate による Step 進捗管理

co-architect は長時間ワークフロー（9 Step）のため、主要 Step 開始時に TaskCreate でタスクを登録しなければならない（MUST）。

#### Scenario: 9 Step の進捗追跡
- **WHEN** co-architect が起動される
- **THEN** 主要 Step のタスクが順次登録・更新され、ユーザーが CLI 上で進捗を確認できる

### Requirement: architecture/ ファイルへの DDD 構造出力

Step 2 の探索で確認された設計項目は、architecture/ 配下の適切なファイルに書き込まなければならない（MUST）。具体的には vision.md, domain/model.md, domain/glossary.md, domain/contexts/*.md, decisions/*.md, contracts/*.md が対象である（SHALL）。

#### Scenario: 設計探索結果の永続化
- **WHEN** /dev:explore で設計項目が確認される
- **THEN** 各項目が architecture/ 配下の対応するファイルに追記・更新される
