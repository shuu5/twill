## ADDED Requirements

### Requirement: chain-runner.sh quick-guard コマンド

`chain-runner.sh quick-guard` コマンドを追加する。ブランチから Issue 番号を抽出し、state または gh API で quick 判定を行い、quick なら exit 1、そうでなければ exit 0 を返さなければならない（SHALL）。

#### Scenario: state に is_quick=true が存在する場合

- **WHEN** ブランチが `feat/123-xxx` の形式で、`state-read.sh --field is_quick` が `"true"` を返す
- **THEN** exit 1 を返す（quick Issue と判定）

#### Scenario: state に is_quick=false が存在する場合

- **WHEN** ブランチが `feat/123-xxx` の形式で、`state-read.sh --field is_quick` が `"false"` を返す
- **THEN** exit 0 を返す（非 quick Issue と判定）

#### Scenario: state が未設定で gh API fallback する場合

- **WHEN** state-read.sh が空文字を返し、`detect_quick_label()` が `true` を返す
- **THEN** exit 1 を返す

#### Scenario: ブランチから Issue 番号を抽出できない場合

- **WHEN** ブランチ名が `feat/xxx-no-number` のような形式で Issue 番号を含まない
- **THEN** exit 0 を返す（保守的にスキップ）

### Requirement: workflow-test-ready quick ガード

`workflow-test-ready/SKILL.md` の Step 1 の前に quick ガードセクションを追加しなければならない（MUST）。`chain-runner.sh quick-guard` の終了コードに基づき、quick Issue の場合は全ステップをスキップして終了する。

#### Scenario: quick Issue で workflow-test-ready が呼ばれた場合

- **WHEN** `chain-runner.sh quick-guard` が exit 1 を返す
- **THEN** 「quick Issue のため test-ready をスキップします」メッセージを出力し、以降の全ステップを実行せずに終了する

#### Scenario: 非 quick Issue で workflow-test-ready が呼ばれた場合

- **WHEN** `chain-runner.sh quick-guard` が exit 0 を返す
- **THEN** ガードを通過して Step 1 以降の通常フローを継続する

## MODIFIED Requirements

### Requirement: deps.yaml chain-runner.sh エントリ更新

`deps.yaml` の chain-runner.sh コンポーネントに `quick-guard` コマンドを追記しなければならない（SHALL）。

#### Scenario: deps.yaml 更新後に loom check が通る

- **WHEN** chain-runner.sh に quick-guard コマンドを追加し deps.yaml を更新した後、`loom check` を実行する
- **THEN** エラーなく完了する
