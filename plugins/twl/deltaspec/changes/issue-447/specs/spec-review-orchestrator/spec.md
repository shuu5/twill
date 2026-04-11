## ADDED Requirements

### Requirement: spec-review-orchestrator スクリプトの存在

`plugins/twl/scripts/spec-review-orchestrator.sh` が存在しなければならない（SHALL）。

#### Scenario: スクリプト実行
- **WHEN** `spec-review-orchestrator.sh --issues-dir DIR --output-dir DIR` が実行される
- **THEN** `--issues-dir` 内の全 `issue-*.json` ファイルに対し、それぞれ独立した tmux cld セッションが起動される

### Requirement: Issue ごとの独立セッション起動

オーケストレーターは各 Issue を独立した tmux ウィンドウで処理しなければならない（SHALL）。

#### Scenario: N Issue の並列処理
- **WHEN** `--issues-dir` に 5 個の `issue-*.json` が存在する
- **THEN** 最大 `MAX_PARALLEL`（デフォルト 3）個のセッションを同時に起動し、バッチ完了後に次のバッチを起動する

#### Scenario: 1 Issue の処理
- **WHEN** `--issues-dir` に 1 個の `issue-*.json` が存在する
- **THEN** 1 個のセッションが起動され正常完了する

### Requirement: MAX_PARALLEL 環境変数による制御

`MAX_PARALLEL` 環境変数でバッチサイズを制御できなければならない（SHALL）。

#### Scenario: デフォルト値
- **WHEN** `MAX_PARALLEL` が未設定
- **THEN** デフォルト値 3 でバッチ処理が行われる

#### Scenario: カスタム値
- **WHEN** `MAX_PARALLEL=5` を設定して実行する
- **THEN** 最大 5 セッションが同時に起動される

### Requirement: 結果ファイルへの書き出し

各 cld セッションは `/twl:issue-spec-review` の実行結果を `--output-dir/issue-{N}-result.txt` に書き出さなければならない（SHALL）。

#### Scenario: 全セッション完了後の結果収集
- **WHEN** 全 cld セッションが完了する
- **THEN** `--output-dir` 内に各 Issue の `issue-{N}-result.txt` が存在し、親セッションが読み込める

## MODIFIED Requirements

### Requirement: workflow-issue-refine Step 3b のオーケストレーター委譲

`workflow-issue-refine` Step 3b は LLM ループではなく `spec-review-orchestrator.sh` を呼び出さなければならない（SHALL）。

#### Scenario: 複数 Issue の spec-review
- **WHEN** Step 3b が N Issue を処理する
- **THEN** `spec-review-orchestrator.sh` が呼び出され、LLM が直接 `/twl:issue-spec-review` を N 回呼ぶことはない

#### Scenario: 結果の受け取り
- **WHEN** オーケストレーターが完了する
- **THEN** Step 3c は `--output-dir` から結果ファイルを読み込んで処理を継続する

### Requirement: deps.yaml への spec-review-orchestrator 登録

`plugins/twl/deps.yaml` に `spec-review-orchestrator` が script エントリとして登録され、`workflow-issue-refine` の calls に追加されなければならない（SHALL）。

#### Scenario: deps.yaml 整合性
- **WHEN** `loom --check` を実行する
- **THEN** spec-review-orchestrator のエントリが正常に検証される
