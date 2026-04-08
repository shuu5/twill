# Architecture Design

co-architect による対話的アーキテクチャ構築ワークフロー（探索 → 完全性チェック → Phase 計画 → Issue 分解 → 一括作成）を定義するシナリオ。

## Scenario: 通常フロー（Step 1〜8）

- **WHEN** co-architect が `--group` なしで実行される
- **THEN** プロジェクトのコンテキスト収集（README, CLAUDE.md, 既存 architecture/）が行われる
- **AND** `/twl:explore` で対話的アーキテクチャ探索が実行される
- **AND** 確定した設計事項が architecture/ 配下の対応ファイルに Write される
- **AND** `/twl:architect-completeness-check` で完全性チェックが実行される
- **AND** Phase 計画がユーザーとの対話で確定され `phases/<NN>.md` に書き出される
- **AND** `/twl:architect-decompose` で Issue 候補が分解される
- **AND** ユーザー確認後に `/twl:architect-issue-create` で Issue が一括作成される
- **AND** Project Board 同期が実行される

## Scenario: --group 分岐（Context グループ深堀り）

- **WHEN** `co-architect --group <context-name>` が実行される
- **THEN** `/twl:architect-group-refine <context-name>` が実行される
- **AND** Step 1〜8 はスキップされる

## Scenario: 完全性チェックの WARNING 対応

- **WHEN** `/twl:architect-completeness-check` が WARNING を返す
- **THEN** 不足箇所がユーザーに提示される
- **AND** 補完する場合は Step 2（explore）に戻り探索が再開される
- **AND** 補完しない場合は Step 4（Phase 計画）に進む

## Scenario: architecture/ ファイル構造

- **WHEN** 対話的探索で設計事項が確定する
- **THEN** ビジョンは `architecture/vision.md` に Write される
- **AND** ドメインモデルは `architecture/domain/model.md` に Write される
- **AND** 用語定義は `architecture/domain/glossary.md` に Write される
- **AND** Bounded Context は `architecture/domain/contexts/<name>.md` に Write される
- **AND** 設計判断は `architecture/decisions/<NNNN>-<title>.md` に Write される
- **AND** API 境界は `architecture/contracts/<name>.md` に Write される

## Scenario: Issue 候補の整合性チェック

- **WHEN** `/twl:architect-decompose` が Issue 候補を出力する
- **THEN** 6 項目の整合性チェック結果が表示される
- **AND** WARNING がある場合は修正が提案される

## Scenario: ユーザー確認による Issue 作成制御

- **WHEN** Issue 候補リストが確定する
- **THEN** AskUserQuestion で最終確認が求められる
- **AND** [A] 承認 → Issue 一括作成に進む
- **AND** [B] 修正 → 修正後 decompose から再実行
- **AND** [C] キャンセル → 終了（architecture/ は保持）

## Scenario: 完了後の案内

- **WHEN** アーキテクチャ構築と Issue 作成が完了する
- **THEN** `/twl:co-autopilot` での一括実装、または `/twl:workflow-setup #N` での個別実装が案内される
