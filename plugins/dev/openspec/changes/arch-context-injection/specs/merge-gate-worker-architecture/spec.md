## MODIFIED Requirements

### Requirement: merge-gate 動的レビュアーへの worker-architecture 自動追加

merge-gate は動的レビュアー構築フェーズで、`[ -d "$(git rev-parse --show-toplevel)/architecture" ]` を評価し、`architecture/` が存在する場合 `worker-architecture` を specialist リストに追加しなければならない（SHALL）。`architecture/` が存在しないプロジェクトでは追加してはならない（SHALL NOT）。

#### Scenario: architecture/ 存在プロジェクト
- **WHEN** merge-gate が動的レビュアーを構築し、プロジェクトルートに `architecture/` が存在する
- **THEN** `worker-architecture` が specialist リストに追加され、他の specialist と並列で Task spawn される

#### Scenario: architecture/ 非存在プロジェクト
- **WHEN** merge-gate が動的レビュアーを構築し、プロジェクトルートに `architecture/` が存在しない
- **THEN** `worker-architecture` は specialist リストに追加されず、merge-gate の動作は従来通りとなる

### Requirement: deps.yaml merge-gate.calls への worker-architecture 追加

`deps.yaml` の `merge-gate.calls` セクションに `worker-architecture` を追加しなければならない（SHALL）。

#### Scenario: deps.yaml 整合性
- **WHEN** loom check を実行する
- **THEN** `merge-gate.calls` に `worker-architecture` が含まれ、バリデーションが PASS する

## ADDED Requirements

### Requirement: worker-architecture PR diff 入力モード

`worker-architecture` エージェントは `pr_diff` 入力モードをサポートしなければならない（SHALL）。このモードでは：
1. プロジェクトの `architecture/` 配下の ADR・invariants・contracts ファイルを Read する（SHALL）
2. PR diff の内容との整合性を検証する（SHALL）
3. 違反を `architecture-violation` カテゴリの Finding として出力する（SHALL）
4. 既存の `plugin_path` モードの動作を変更してはならない（SHALL NOT）

#### Scenario: PR diff モードで ADR 違反を検出
- **WHEN** merge-gate から `pr_diff` モードで worker-architecture が呼び出され、PR diff が ADR と矛盾する変更を含む
- **THEN** severity=CRITICAL、category=architecture-violation の Finding が出力され、confidence >= 80 の場合 merge-gate は REJECT を返す

#### Scenario: PR diff モードで違反なし
- **WHEN** merge-gate から `pr_diff` モードで worker-architecture が呼び出され、PR diff が architecture と整合している
- **THEN** status=PASS、findings=[] が出力される

### Requirement: specialist-output-schema architecture-violation カテゴリ

`contracts/specialist-output-schema.md` の `category` 定義に `architecture-violation` を追加しなければならない（SHALL）。全 specialist はこのカテゴリを使用可能となる。

#### Scenario: architecture-violation カテゴリ使用
- **WHEN** specialist が architecture/ADR/invariant との不整合を検出する
- **THEN** Finding の category フィールドに `architecture-violation` を設定可能であり、スキーマバリデーションが通過する
