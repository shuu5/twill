## ADDED Requirements

### Requirement: AUTOPILOT_DIR env 伝搬の bats テスト

`autopilot-launch.sh` が Worker 起動コマンドに `AUTOPILOT_DIR` を含めることを、bats テストで検証しなければならない（SHALL）。`tests/bats/scripts/autopilot-launch-autopilotdir.bats` を新規作成し、以下のシナリオを実装すること。

#### Scenario: カスタム AUTOPILOT_DIR が Worker 起動コマンドに渡される
- **WHEN** `--autopilot-dir /tmp/custom-dir` を指定して `autopilot-launch.sh` を起動する
- **THEN** Worker 起動コマンド（tmux new-window の引数）に `AUTOPILOT_DIR=/tmp/custom-dir` が含まれている

#### Scenario: デフォルト AUTOPILOT_DIR が PROJECT_ROOT/.autopilot にフォールバックする
- **WHEN** `AUTOPILOT_DIR` 環境変数を設定せず co-autopilot を起動する
- **THEN** `autopilot-init.sh` が `$PROJECT_ROOT/.autopilot` にディレクトリを作成する

#### Scenario: AUTOPILOT_DIR カスタム設定時に state ファイルが指定パスに書かれる
- **WHEN** `AUTOPILOT_DIR=/tmp/foo` を設定した状態で `state write --type issue --issue N` を実行する
- **THEN** state ファイルが `/tmp/foo/issues/issue-N.json` に作成される
- **THEN** `$PROJECT_ROOT/.autopilot/issues/issue-N.json` は作成されない

### Requirement: co-autopilot SKILL.md に state file 解決ルールを明記

`co-autopilot/SKILL.md` に「state file 解決ルール」セクションを追加しなければならない（SHALL）。`AUTOPILOT_DIR` が SSOT として機能すること、および `autopilot-init.sh` L9 の既存実装への参照を含めること。

#### Scenario: SKILL.md に state file 解決ルールセクションが存在する
- **WHEN** `co-autopilot/SKILL.md` を参照する
- **THEN** `AUTOPILOT_DIR` のデフォルト値（`$PROJECT_ROOT/.autopilot`）と override 方法が記載されている
- **THEN** `autopilot-init.sh` L9 の実装への参照が含まれている
- **THEN** Pilot→Worker spawn 時に `AUTOPILOT_DIR` が `env` 経由で継承されることが明記されている

### Requirement: 既存 bats テストの回帰チェック

変更後も既存の bats テストが全て通らなければならない（MUST）。`autopilotdir-state-split.bats` の既存テストは変更しないこと。

#### Scenario: 既存テストが引き続き通る
- **WHEN** `bats plugins/twl/tests/bats/scripts/autopilotdir-state-split.bats` を実行する
- **THEN** 全テストが PASS する
