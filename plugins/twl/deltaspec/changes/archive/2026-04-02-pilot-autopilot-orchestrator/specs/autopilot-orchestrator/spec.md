## ADDED Requirements

### Requirement: autopilot-orchestrator.sh Phase ループ実行

`scripts/autopilot-orchestrator.sh` は plan.yaml の指定 Phase について、batch 分割・Worker 起動・ポーリング・merge-gate・window 管理を一括実行しなければならない（SHALL）。

#### Scenario: 単一 Phase の正常実行
- **WHEN** `--plan plan.yaml --phase 1 --session session.json --project-dir DIR --autopilot-dir DIR` で実行
- **THEN** Phase 1 の Issue リストを取得し、MAX_PARALLEL で batch 分割し、各 batch の Worker 起動→ポーリング→merge-gate→window kill を順次実行する
- **THEN** 全 Issue が done/failed になった後、stdout に JSON 形式の Phase 完了レポートを出力して終了する

#### Scenario: batch 分割（MAX_PARALLEL 超過）
- **WHEN** Phase 内の有効 Issue 数が MAX_PARALLEL（デフォルト 4）を超える
- **THEN** MAX_PARALLEL 個ずつの batch に分割し、各 batch を逐次処理する

#### Scenario: skip/done Issue のフィルタリング
- **WHEN** Phase 内に status=done または autopilot-should-skip.sh が exit 0 の Issue がある
- **THEN** これらの Issue を有効リストから除外し、Worker 起動をスキップする

### Requirement: ポーリングの統合

orchestrator はポーリングロジック（state-read.sh + crash-detect.sh）をスクリプト内に統合しなければならない（MUST）。

#### Scenario: ポーリング正常完了
- **WHEN** batch 内の全 Issue が done/failed/merge-ready のいずれかに遷移
- **THEN** ポーリングループを終了し、merge-ready Issue に対して merge-gate を実行する

#### Scenario: ポーリングタイムアウト
- **WHEN** MAX_POLL 回（デフォルト 360 回 × 10 秒）に達しても running の Issue が残る
- **THEN** 残りの running Issue を state-write.sh で failed（poll_timeout）に遷移させる

#### Scenario: crash-detect 統合
- **WHEN** ポーリング中に crash-detect.sh が exit 2 を返す
- **THEN** 当該 Issue のポーリングを終了する（crash-detect.sh が state を failed に遷移済み）

### Requirement: merge-gate と window kill の原子的実行

merge-gate 判定後の window kill は、merge-gate-execute.sh の終了直後に実行しなければならない（SHALL）。Pilot LLM の介入なしに原子的に処理する。

#### Scenario: merge 成功時の window cleanup
- **WHEN** merge-gate-execute.sh が exit 0 で完了（merge 成功）
- **THEN** merge-gate-execute.sh 内で tmux kill-window が実行済みのため、追加の window kill は不要

#### Scenario: merge-gate リジェクト時
- **WHEN** merge-gate-execute.sh が --reject で呼ばれた（リトライ可能）
- **THEN** window は kill せず、Worker に修正指示を送信する（tmux send-keys）

### Requirement: chain 遷移停止検知と自動 nudge

Worker の chain が停止した場合（出力パターンマッチで検知）、自動的に tmux send-keys で次コマンドを送信しなければならない（SHALL）。

#### Scenario: chain 停止検知
- **WHEN** Worker の tmux pane 出力に chain 完了パターン（例: `setup chain 完了`、`>>> 提案完了`）が検出され、NUDGE_TIMEOUT 秒（デフォルト 30 秒）以内に新しい入力がない
- **THEN** tmux send-keys で適切な次コマンドを送信する

#### Scenario: nudge 最大回数制限
- **WHEN** 同一 Issue に対して MAX_NUDGE 回（デフォルト 3 回）の nudge を送信済み
- **THEN** それ以上の nudge を送信せず、ログに警告を出力する

### Requirement: Phase 完了レポート出力

Phase 完了時に JSON 形式のレポートを stdout に出力しなければならない（MUST）。

#### Scenario: Phase 完了レポート
- **WHEN** Phase 内の全 Issue の処理が完了
- **THEN** 以下の構造の JSON を stdout に出力する:
  ```json
  {
    "signal": "PHASE_COMPLETE",
    "phase": 1,
    "results": {
      "done": [123, 124],
      "failed": [],
      "skipped": [125]
    },
    "changed_files": ["file1.ts", "file2.sh"]
  }
  ```

### Requirement: サマリー集計

`--summary` フラグ指定時、全 Phase の結果を集約したサマリーレポートを出力しなければならない（SHALL）。

#### Scenario: サマリー生成
- **WHEN** `--summary --session session.json --autopilot-dir DIR` で実行
- **THEN** 全 issue-{N}.json を集約し、done/failed/skipped の件数と詳細を JSON で stdout に出力する

## MODIFIED Requirements

### Requirement: co-autopilot SKILL.md の Step 4 簡素化

co-autopilot SKILL.md の Step 4（Phase ループ）は orchestrator 呼び出しに変更しなければならない（MUST）。Pilot LLM は orchestrator の JSON 出力を受けて retrospective/cross-issue のみを実行する。

#### Scenario: Phase 実行の委譲
- **WHEN** co-autopilot が Phase 実行に到達
- **THEN** `bash scripts/autopilot-orchestrator.sh --plan $PLAN_FILE --phase $P ...` を実行し、JSON レポートをパースして LLM 判断（retrospective/cross-issue）を実行する

#### Scenario: Emergency Bypass 時の手動パス
- **WHEN** orchestrator 自体に障害がある場合
- **THEN** 既存の autopilot-phase-execute.md / autopilot-poll.md を直接参照して手動実行する（後方互換性維持）
