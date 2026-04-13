# Architecture Design

co-architect による対話的アーキテクチャ構築ワークフロー（探索 → 完全性チェック）を定義するシナリオ。
Issue 化は co-issue に委譲（Issue #560）。

## Scenario: 通常フロー（Step 0〜3）

- **WHEN** co-architect が `--group` なしで実行される
- **THEN** プロジェクトのコンテキスト収集（README, CLAUDE.md, 既存 architecture/）が行われる
- **AND** `/twl:explore` で対話的アーキテクチャ探索が実行される
- **AND** 確定した設計事項が architecture/ 配下の対応ファイルに Write される
- **AND** `/twl:architect-completeness-check` で完全性チェックが実行される
- **AND** `/twl:co-issue` および `/twl:co-autopilot` への案内が出力される

## Scenario: --group 分岐（Context グループ深堀り）

- **WHEN** `co-architect --group <context-name>` が実行される
- **THEN** `/twl:architect-group-refine <context-name>` が実行される
- **AND** Step 1〜3 はスキップされる

## Scenario: 完全性チェックの WARNING 対応

- **WHEN** `/twl:architect-completeness-check` が WARNING を返す
- **THEN** 不足箇所がユーザーに提示される
- **AND** 補完する場合は Step 2（explore）に戻り探索が再開される
- **AND** 補完しない場合は完了案内を出力する

## Scenario: architecture/ ファイル構造

- **WHEN** 対話的探索で設計事項が確定する
- **THEN** ビジョンは `architecture/vision.md` に Write される
- **AND** ドメインモデルは `architecture/domain/model.md` に Write される
- **AND** 用語定義は `architecture/domain/glossary.md` に Write される
- **AND** Bounded Context は `architecture/domain/contexts/<name>.md` に Write される
- **AND** 設計判断は `architecture/decisions/<NNNN>-<title>.md` に Write される
- **AND** API 境界は `architecture/contracts/<name>.md` に Write される

## Scenario: 完了後の案内

- **WHEN** アーキテクチャ構築（Step 0-3）が完了する
- **THEN** `/twl:co-issue` での Issue 群作成、または `/twl:co-autopilot` での一括実装が案内される
