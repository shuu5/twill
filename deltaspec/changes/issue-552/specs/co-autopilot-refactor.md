## ADDED Requirements

### Requirement: autopilot-pilot-wakeup-loop atomic の新規作成

`plugins/twl/commands/autopilot-pilot-wakeup-loop.md` が存在し、co-autopilot Step 4 の orchestrator 起動・PHASE_COMPLETE 検知ループ・stagnation 検知・Silence heartbeat を包含しなければならない（SHALL）。

#### Scenario: PHASE_COMPLETE 検知
- **WHEN** orchestrator が `PHASE_COMPLETE` シグナルをトレースログに出力した時
- **THEN** atomic が検知し Step 4.5 へ制御を返すこと

#### Scenario: stagnation 検知
- **WHEN** Worker の `updated_at` が `AUTOPILOT_STAGNATE_SEC`（デフォルト 900 秒）以上古い時
- **THEN** atomic が stall Worker を特定し `session-comm.sh inject-file` 経由で回復信号を送信すること

#### Scenario: Silence heartbeat
- **WHEN** 全 Worker の `updated_at` が 5 分以上無変化かつ PHASE_COMPLETE 未検知の時
- **THEN** atomic が `tmux capture-pane` で input-waiting パターンを検査し、検知時は state file に `input_waiting_detected` を記録すること

#### Scenario: 状況精査モード
- **WHEN** `MAX_WAIT_MINUTES`（30 分）を超過した時
- **THEN** atomic が全 Worker の状態を精査し、全 Worker が terminal 状態なら Step 4.5 へ進み、stagnation Worker が存在すれば回復を試みること

### Requirement: deps.yaml への autopilot-pilot-wakeup-loop 登録

`deps.yaml` に `autopilot-pilot-wakeup-loop`（type: atomic、spawnable_by: [controller]）が登録され、co-autopilot.calls に `atomic: autopilot-pilot-wakeup-loop` が追加されなければならない（SHALL）。

#### Scenario: deps.yaml 整合性
- **WHEN** `twl --check` を実行した時
- **THEN** autopilot-pilot-wakeup-loop が登録済みでバリデーションが通ること

## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md 本文行数の削減

`plugins/twl/skills/co-autopilot/SKILL.md` の本文行数（frontmatter 除く）が 200 行未満でなければならない（SHALL）。

#### Scenario: 行数制限の達成
- **WHEN** frontmatter（`---` から `---`）を除いた本文行数をカウントした時
- **THEN** その行数が 200 未満であること

### Requirement: Step 4 の atomic 委譲形式への書き換え

co-autopilot SKILL.md の Step 4 は `commands/autopilot-pilot-wakeup-loop.md` を Read → 実行する形式でなければならない（SHALL）。インライン実装（nohup・ScheduleWakeup ループ）を SKILL.md 内に持ってはならない（SHALL NOT）。

#### Scenario: Step 4 委譲
- **WHEN** co-autopilot が Phase ループ（Step 4）を実行する時
- **THEN** `autopilot-pilot-wakeup-loop` atomic への委譲が行われること

### Requirement: Step 4.5 の atomic 委譲形式への統一

Step 4.5 は narrative 形式ではなく atomic 委譲形式（`commands/<name>.md を Read → 実行`）でなければならない（SHALL）。

#### Scenario: Step 4.5 形式
- **WHEN** PHASE_COMPLETE 受信後のサニティチェックを実行する時
- **THEN** 各 atomic（autopilot-phase-sanity, autopilot-pilot-precheck 等）への委譲指示のみが記述されていること

### Requirement: autopilot.md への documentation 移動

`architecture/domain/contexts/autopilot.md` に Recovery Procedures・State Management 追記・Constraints 充実が反映されなければならない（SHALL）。SKILL.md の対応セクション（chain 停止時の復旧手順・state file 解決ルール・不変条件詳細記述）はリンクのみに置き換えられなければならない（SHALL）。

#### Scenario: 復旧手順の外部化
- **WHEN** autopilot.md を確認した時
- **THEN** `Recovery Procedures` セクションが存在し、orchestrator 再起動手順と手動 workflow inject 手順が記載されていること

#### Scenario: SKILL.md のリンク残置
- **WHEN** co-autopilot SKILL.md の該当箇所を確認した時
- **THEN** 削除されたセクションの代わりに autopilot.md 該当セクションへの Markdown リンクが存在すること

### Requirement: twl ツールチェーン全通過

変更後に `twl --check`・`twl --validate`・`twl --audit`（相当）が全通過しなければならない（SHALL）。

#### Scenario: ツールチェーン通過
- **WHEN** `twl --check` および `twl update-readme` を実行した時
- **THEN** エラーなく完了すること
