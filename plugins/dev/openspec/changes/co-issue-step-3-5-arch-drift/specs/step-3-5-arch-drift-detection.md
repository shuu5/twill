# Spec: co-issue Step 3.5 Architecture Drift Detection

## ADDED Requirements

### Requirement: Step 3.5 の挿入

co-issue の Phase 3 完了後・Phase 4 開始前に Step 3.5（Architecture Drift Detection）が実行されなければならない（SHALL）。

#### Scenario: Phase 3 完了後に Step 3.5 が実行される
- **WHEN** Phase 3 の specialist レビューが完了し TaskUpdate Phase 3 → completed が呼ばれた後
- **THEN** CRITICAL ブロックがない場合、Step 3.5 が実行される

#### Scenario: CRITICAL ブロック中は Step 3.5 をスキップする
- **WHEN** Phase 3c で CRITICAL findings が検出されブロック状態にある
- **THEN** Step 3.5 を実行せずに Phase 4 ブロックのメッセージのみ表示する

---

### Requirement: architecture/ 非存在時のスキップ

`architecture/` ディレクトリが存在しない、または `architecture/domain/glossary.md` が存在しない場合、Step 3.5 全体をスキップしなければならない（SHALL）。出力を一切行わず Phase 4 に進む。

#### Scenario: architecture/ なしプロジェクトでスキップ
- **WHEN** `architecture/domain/glossary.md` が存在しない
- **THEN** Step 3.5 を実行せず出力なしで Phase 4 に進む

---

### Requirement: 明示的シグナル検出

Issue body に `<!-- arch-ref-start -->` タグが含まれる場合、明示的シグナルとして検出しなければならない（SHALL）。

#### Scenario: arch-ref タグあり
- **WHEN** 精緻化済み Issue の body に `<!-- arch-ref-start -->` と `<!-- arch-ref-end -->` が含まれる
- **THEN** タグ間のパス（例: `architecture/domain/contexts/autopilot.md`）を抽出し、明示的シグナルとして記録する

#### Scenario: arch-ref タグなし
- **WHEN** Issue body に `<!-- arch-ref-start -->` タグが含まれない
- **THEN** 明示的シグナルなし（他シグナルの評価に影響しない）

---

### Requirement: 構造的シグナル検出

glossary.md の MUST 用語または `architecture/` 配下のファイル名が Issue body で言及される場合、構造的シグナルとして検出しなければならない（SHALL）。

#### Scenario: 不変条件への言及を検出
- **WHEN** Issue body に glossary.md の MUST 用語（例: 「不変条件B」「WorkerSession」）が含まれる
- **THEN** 構造的シグナルあり、言及された用語を記録する

#### Scenario: architecture ファイル名への言及を検出
- **WHEN** Issue body に `architecture/` 配下のファイル名パターン（例: `contexts/autopilot.md`）が含まれる
- **THEN** 構造的シグナルあり、参照ファイルを記録する

---

### Requirement: ヒューリスティックシグナル検出

作成予定 Issue の recommended_labels に ctx/* ラベルが 3 つ以上含まれる場合、ヒューリスティックシグナルとして検出しなければならない（SHALL）。

#### Scenario: ctx/* ラベル 3 件以上
- **WHEN** 1 件以上の Issue candidate の recommended_labels に ctx/* ラベルが 3 件以上含まれる
- **THEN** ヒューリスティックシグナルあり、対象 Issue を記録する

#### Scenario: ctx/* ラベル 2 件以下
- **WHEN** 全 Issue candidate の recommended_labels の ctx/* ラベルが 2 件以下
- **THEN** ヒューリスティックシグナルなし

---

### Requirement: シグナルあり時の INFO 出力

シグナルが 1 件以上検出された場合、INFO レベルで影響 Issue の一覧と `/dev:co-architect` の実行提案を出力しなければならない（SHALL）。

#### Scenario: シグナルあり時の出力
- **WHEN** 明示的・構造的・ヒューリスティックのいずれかで 1 件以上のシグナルが検出される
- **THEN** 以下の形式で出力する:
  ```
  [INFO] 以下の Issue が architecture spec に影響する可能性があります:
    "<タイトル>": explicit reference (architecture/...)
    "<タイトル>": invariant change (<用語>)
    "<タイトル>": cross-context impact (ctx/* labels: N)
  architecture spec の事前更新を検討してください: /dev:co-architect
  ```

#### Scenario: 非ブロッキング
- **WHEN** INFO 出力後
- **THEN** ユーザー入力を待たずに Phase 4 に進む（co-issue フローを停止してはならない）

#### Scenario: シグナルなし時は出力しない
- **WHEN** 全シグナルが 0 件
- **THEN** Step 3.5 の出力を一切行わず Phase 4 に進む
