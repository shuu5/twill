## MODIFIED Requirements

### Requirement: orchestrator stdout を JSON レポートのみに限定

`autopilot-orchestrator.sh` のループ内 `echo "[orchestrator]..."` 全行は stderr に出力しなければならない（SHALL）。stdout には `generate_phase_report` の JSON 出力のみが流れる。

#### Scenario: Issue 進捗ログが stderr に出力される
- **WHEN** orchestrator が Phase を実行し Issue の進捗ログを出力する
- **THEN** `echo "[orchestrator] Issue #N: ..."` の全行が stderr に出力され、stdout には出力されない

#### Scenario: Phase JSON レポートが stdout に出力される
- **WHEN** orchestrator が Phase を完了し `generate_phase_report` を呼び出す
- **THEN** JSON レポートが stdout に出力され、`REPORT=$(bash ...)` で Pilot が受け取れる

### Requirement: logs ディレクトリが自動作成される

orchestrator の Phase 実行開始時に `mkdir -p "$AUTOPILOT_DIR/logs"` を実行しなければならない（SHALL）。

#### Scenario: logs ディレクトリが存在しない場合
- **WHEN** `$AUTOPILOT_DIR/logs/` が存在しない状態で orchestrator が起動する
- **THEN** `mkdir -p` により自動作成され、ログファイルへのリダイレクトが成功する

## MODIFIED Requirements

### Requirement: co-autopilot が orchestrator stderr をログファイルに転送

`co-autopilot/SKILL.md` の orchestrator 呼び出しは `2>"$AUTOPILOT_DIR/logs/phase-${P}.log"` 形式で stderr をリダイレクトしなければならない（MUST）。

#### Scenario: Phase 実行中の stderr がログファイルに記録される
- **WHEN** Pilot が `REPORT=$(bash autopilot-orchestrator.sh ... 2>"$AUTOPILOT_DIR/logs/phase-${P}.log")` を実行する
- **THEN** orchestrator の進捗ログが `phase-N.log` に保存され、Pilot の Bash tool output には JSON レポートのみが含まれる

#### Scenario: Pilot context にログが混入しない
- **WHEN** orchestrator が60分以上動作し大量の進捗ログを出力する
- **THEN** Pilot の context window に入るのは最終的な JSON レポートのみである
