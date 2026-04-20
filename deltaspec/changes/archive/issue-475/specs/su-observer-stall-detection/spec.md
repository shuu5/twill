## ADDED Requirements

### Requirement: 監視チャンネルマトリクス

su-observer は supervise モードの 1 iteration で5チャンネルを並行実行しなければならない（SHALL）。SKILL.md Step 1 に以下のマトリクスを追加する:

| チャンネル | 目的 | 閾値/間隔 |
|---|---|---|
| Monitor tool (Pilot) | tail streaming | 随時 |
| `cld-observe-loop --pattern 'ap-*' --interval 180` | Worker 群 polling | 3 分 |
| `.autopilot/issues/issue-*.json` mtime 監視 | state stagnate 検知 | `AUTOPILOT_STAGNATE_SEC` デフォルト 600s |
| `session-comm.sh capture` (ad-hoc) | 実体確認 | on-demand |
| `gh pr list` (Pilot 向け) | state.pr と実体の差分検知 | Step 4 Wave 管理時 |

#### Scenario: Worker stall 検知
- **WHEN** co-autopilot 起動後、cld-observe-loop を `--pattern 'ap-*' --interval 180` で起動し、いずれかの Worker の state file `updated_at` が `AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）以上更新されていない
- **THEN** su-observer は WARN を出力し、intervention-catalog の pattern-7 照合を実行しなければならない（SHALL）

#### Scenario: 監視チャンネル並行実行
- **WHEN** su-observer が co-autopilot supervise モードに入る
- **THEN** Monitor tool（Pilot tail）と cld-observe-loop（Worker 群）を同時に起動しなければならない（SHALL）。どちらか一方のみの起動は禁止とする

### Requirement: state stagnate 検知（observe-once 拡張）

observe-once は snapshot 取得と合わせて state file の mtime チェックを実行しなければならない（SHALL）。

#### Scenario: stagnate ファイル検出
- **WHEN** observe-once を実行し、`.autopilot/issues/issue-*.json` のいずれかの mtime が `AUTOPILOT_STAGNATE_SEC` 秒以上古い
- **THEN** JSON 出力の `stagnate_files` 配列に該当ファイルパスを含め、stderr に `WARN: state stagnate detected: <path>` を出力しなければならない（SHALL）。JSON stdout と WARN stderr は分離すること

#### Scenario: stagnate なし
- **WHEN** observe-once を実行し、全 state file の mtime が `AUTOPILOT_STAGNATE_SEC` 秒以内
- **THEN** `stagnate_files` は空配列 `[]` を出力し、WARN は出力しない（SHALL）

### Requirement: Worker idle 検知パターン（intervention-catalog pattern-7）

intervention-catalog は「state stagnate かつ worker pane に完了シグナルあり」を Layer 0 Auto 介入として定義しなければならない（SHALL）。

#### Scenario: 自動回復（pattern-7）
- **WHEN** state `updated_at` が 600 秒以上古い AND 対象 Worker pane の tail に `>>> 実装完了:` を含む文字列が検出される
- **THEN** su-observer は Layer 0 Auto として `/twl:workflow-pr-verify --spec issue-<N>` を対象 Worker window に inject し、InterventionRecord を記録しなければならない（SHALL）

#### Scenario: 検出条件が部分的にしか満たされない場合
- **WHEN** state stagnate は検出されたが worker pane に `>>> 実装完了:` が含まれない
- **THEN** pattern-7 ではなく Layer 1 Confirm（パターン4: Worker 長時間 idle）として処理しなければならない（SHALL）

## MODIFIED Requirements

### Requirement: observe-once JSON 出力スキーマ拡張

observe-once の JSON 出力スキーマは `stagnate_files` フィールドを含まなければならない（SHALL）。

#### Scenario: JSON フィールド追加
- **WHEN** observe-once を実行する
- **THEN** 出力 JSON に `stagnate_files: string[]` フィールドを含まなければならない（SHALL）。既存フィールド（`window`, `timestamp`, `lines`, `capture`, `session_state`）は変更しない
