## ADDED Requirements

### Requirement: health-check スクリプト

`scripts/health-check.sh` は Worker の論理的異常を検知し、exit code と stdout で結果を返さなければならない（SHALL）。crash-detect.sh（プロセス死亡）とは責務が異なり、重複してはならない（MUST NOT）。

#### Scenario: chain 停止検知
- **WHEN** state-read.sh の updated_at と現在時刻の差分が `DEV_HEALTH_CHAIN_STALL_MIN`（デフォルト 10）分を超える
- **THEN** exit code 1 を返し、stdout に `chain_stall` と経過分数を出力しなければならない（SHALL）

#### Scenario: エラー出力検知
- **WHEN** `tmux capture-pane -t "$WINDOW_NAME" -p -S -50` の出力に `Error|FATAL|panic|Traceback` パターンが含まれる
- **THEN** exit code 1 を返し、stdout に `error_output` とマッチした行を出力しなければならない（SHALL）

#### Scenario: input-waiting 長時間検知
- **WHEN** session-state.sh が利用可能で、`session-state.sh get "$WINDOW_NAME"` の結果が `input-waiting` であり、その状態が `DEV_HEALTH_INPUT_WAIT_MIN`（デフォルト 5）分以上継続している
- **THEN** exit code 1 を返し、stdout に `input_waiting` と経過分数を出力しなければならない（SHALL）

#### Scenario: session-state.sh 非存在時のフォールバック
- **WHEN** session-state.sh が利用不可能
- **THEN** input-waiting 検知をスキップし、chain 停止とエラー出力の検知のみ実行しなければならない（SHALL）

#### Scenario: 異常なし
- **WHEN** 3 パターンいずれも検知されない
- **THEN** exit code 0 を返し、stdout に何も出力してはならない（MUST NOT）

### Requirement: 閾値の設定可能性

health-check.sh の閾値は環境変数で上書き可能でなければならない（MUST）。

#### Scenario: 環境変数による閾値カスタマイズ
- **WHEN** `DEV_HEALTH_CHAIN_STALL_MIN=20` が設定されている
- **THEN** chain 停止の閾値が 20 分に変更されなければならない（SHALL）

#### Scenario: 環境変数未設定時のデフォルト
- **WHEN** 環境変数が未設定
- **THEN** chain 停止 10 分、input-waiting 5 分のデフォルト値を使用しなければならない（SHALL）

## MODIFIED Requirements

### Requirement: autopilot-phase-execute への health check 統合

autopilot-phase-execute.md の poll ループ内で、STATUS が `running` かつ crash-detect が非検知の場合に health-check.sh を呼び出さなければならない（MUST）。sequential/parallel 両モードで動作しなければならない（SHALL）。

#### Scenario: sequential モードでの health check 実行
- **WHEN** sequential モードで poll 中の Issue の STATUS が `running` かつ crash-detect が正常（exit 0）
- **THEN** health-check.sh を `--issue "$ISSUE" --window "$WINDOW_NAME"` で呼び出さなければならない（SHALL）

#### Scenario: parallel モードでの health check 実行
- **WHEN** parallel モードでバッチ内の各 Issue をポーリング中に STATUS が `running` かつ crash-detect が正常
- **THEN** 各 Issue に対して health-check.sh を呼び出さなければならない（SHALL）

#### Scenario: health check 異常検知時の動作
- **WHEN** health-check.sh が exit code 1 を返す
- **THEN** WARNING ログを出力し、health-report を生成しなければならない（SHALL）。Worker の停止やステータス変更は行ってはならない（MUST NOT）

### Requirement: deps.yaml の更新

autopilot-phase-execute の calls セクションに health-check スクリプトと外部依存を追加しなければならない（MUST）。

#### Scenario: deps.yaml 整合性
- **WHEN** `loom check` を実行
- **THEN** PASS を返さなければならない（MUST）
