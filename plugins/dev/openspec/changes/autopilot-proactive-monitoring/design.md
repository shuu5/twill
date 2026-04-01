## Context

autopilot-poll.md は現在 crash-detect.sh（プロセス死亡検知）のみを実行する。論理的異常（chain 停止、エラー出力、input-waiting 長時間）は検知されず、Worker は MAX_POLL（60分）タイムアウトまで放置される。

#78（session-interop 統合 Phase A）で session-state.sh と session-comm.sh capture が統合済みの前提。/observe は ubuntu-note-system env プラグインの外部スキルであり、本プラグインでは `tmux capture-pane` + パターンマッチで同等の検知を行う。

## Goals / Non-Goals

**Goals:**

- Pilot ポーリングループ内で 3 種類の論理的異常を検知する
- 検知結果を構造化レポートとして `.autopilot/health-reports/` に出力する
- Issue Draft テンプレートを生成し、ユーザーの判断材料を提供する
- 閾値を環境変数で設定可能にする
- crash-detect（プロセス死亡）との責務境界を明確に保つ

**Non-Goals:**

- Worker への自動 inject（安全性の観点から除外）
- 自動修正・自動 Issue 作成（提案のみ）
- /observe スキル自体の実装（外部依存として利用）
- autopilot-poll.md の構造変更（health check は autopilot-phase-execute 側に追加）

## Decisions

### D1: health check の配置場所

autopilot-poll.md ではなく autopilot-phase-execute.md に配置する。理由:
- poll は状態確認に特化すべき（単一責務）
- health check は poll 結果が `running` の場合に追加で実行する判断ロジック
- phase-execute は既に launch → poll → merge-gate のオーケストレーションを担当

### D2: 異常検知の実装方式

スクリプト `scripts/health-check.sh` を新設し、autopilot-phase-execute から呼び出す。理由:
- crash-detect.sh と同じパターン（外部スクリプト化）で一貫性を保つ
- テスト可能性の確保
- LLM 判断不要の機械的な検知処理

### D3: 検知パターンと閾値

| パターン | 検知方法 | デフォルト閾値 | 環境変数 |
|----------|----------|----------------|----------|
| chain 停止 | state-read.sh の updated_at と現在時刻の差分 | 10 分 | `DEV_HEALTH_CHAIN_STALL_MIN` |
| エラー出力 | `tmux capture-pane` + grep パターン | — | — |
| input-waiting | session-state.sh get で状態確認 + 経過時間 | 5 分 | `DEV_HEALTH_INPUT_WAIT_MIN` |

### D4: レポート出力形式

```
.autopilot/health-reports/
  issue-{N}-{timestamp}.md
```

Markdown 形式で以下を含む:
- 検知パターン種別
- tmux capture-pane の出力（最新 50 行）
- Issue Draft テンプレート（タイトル、概要、再現状況）

### D5: autopilot-phase-execute への統合ポイント

sequential/parallel 両モードの poll 後（STATUS == running かつ crash-detect 非検知の場合）に health-check.sh を呼び出す。検知した場合は WARNING ログ出力 + レポート生成のみ。Worker の停止やステータス変更は行わない。

## Risks / Trade-offs

- **外部依存リスク**: session-state.sh / session-comm.sh が存在しない環境では input-waiting 検知が無効化される。chain 停止とエラー出力の検知は独立して動作する
- **誤検知リスク**: chain 停止の閾値が短すぎると正常な長時間処理を異常と判定する。デフォルト 10 分は十分に保守的
- **レポート蓄積**: health-reports/ のクリーンアップは本 Issue のスコープ外。autopilot セッション終了時に手動削除を想定
