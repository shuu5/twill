## ADDED Requirements

### Requirement: monitor-channel-catalog.md が 6 チャネルの標準定義を提供する

`plugins/twl/skills/su-observer/refs/monitor-channel-catalog.md` を新設し（`refs/` ディレクトリも新規作成）、以下の 6 チャネルを bash スニペット付きで定義しなければならない（SHALL）:

- **INPUT-WAIT**: 全 window の approval/input UI 長期滞在（閾値: 即時）
- **PILOT-IDLE**: Pilot の Skedaddling/Frolicking/Background poll 継続（閾値: 5分）
- **STAGNATE**: state file 群の mtime 未更新（閾値: 10分）
- **WORKERS**: worker window 出現・消失（閾値: 即時）
- **PHASE-DONE**: PHASE_COMPLETE 検知（閾値: 即時）
- **NON-TERMINAL**: `>>> 実装完了:` 後の chain 不遷移（閾値: 2分）

#### Scenario: カタログを Read してチャネルを選択できる
- **WHEN** su-observer が Wave 開始時に `refs/monitor-channel-catalog.md` を Read する
- **THEN** 各チャネルの bash スニペットをそのまま Monitor tool 呼び出しに使用できる

#### Scenario: STAGNATE チャネルが監視対象 path を明記する
- **WHEN** monitor-channel-catalog.md の STAGNATE セクションを参照する
- **THEN** `.supervisor/working-memory.md` / `.autopilot/waves/<N>.summary.md` / `.autopilot/checkpoints/*.json` の 3 パスが明記されている

### Requirement: su-observer SKILL.md に monitor-channel-catalog 参照ステップを追記する

`plugins/twl/skills/su-observer/SKILL.md` の Step 0 に `refs/monitor-channel-catalog.md` を Read する旨を追記し、Step 1 の Wave 管理フローに Monitor 起動ステップ（3.5）を挿入しなければならない（MUST）。

#### Scenario: SKILL.md Step 0 にカタログ読み込みが追記される
- **WHEN** su-observer が起動し Step 0 を実行する
- **THEN** `refs/monitor-channel-catalog.md` が Read 対象として明示されている

#### Scenario: Wave 管理時に Monitor が起動される
- **WHEN** su-observer が Wave 管理モードで動作する
- **THEN** Step 3.5 として「Wave 種別に応じたチャネルを選択し Monitor tool を起動する」が実行される

### Requirement: observation-pattern-catalog.md に INPUT-WAIT / PILOT-IDLE / STAGNATE を追記する

`plugins/twl/refs/observation-pattern-catalog.md` の既存フォーマットに従い、INPUT-WAIT / PILOT-IDLE / STAGNATE パターンの problem pattern と介入層（Auto/Confirm/Escalate）を追記しなければならない（SHALL）。

#### Scenario: INPUT-WAIT パターンが catalog に追記される
- **WHEN** observation-pattern-catalog.md を参照する
- **THEN** `[INPUT-WAIT]` パターン、検知条件、介入層（Auto）が定義されている

### Requirement: problem-detect.md が新チャネルを検知対象に含む

`plugins/twl/commands/problem-detect.md` に INPUT-WAIT / PILOT-IDLE / STAGNATE の 3 チャネルを検知対象として追加しなければならない（MUST）。

#### Scenario: problem-detect が approval UI 停止を検知する
- **WHEN** `detect_state` が `input-waiting` を返すウィンドウが存在する
- **THEN** problem-detect が `[INPUT-WAIT]` を報告する

### Requirement: deps.yaml の su-observer エントリに monitor-channel-catalog 参照を追記する

`plugins/twl/deps.yaml` の `su-observer` エントリの `calls:` に `- reference: monitor-channel-catalog` を追記し、`twl check` を通過しなければならない（MUST）。

#### Scenario: twl check が deps.yaml を検証する
- **WHEN** `twl check` を実行する
- **THEN** su-observer と monitor-channel-catalog の依存関係エラーが発生しない
