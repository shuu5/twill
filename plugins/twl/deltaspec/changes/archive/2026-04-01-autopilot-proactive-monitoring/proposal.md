## Why

autopilot の Pilot は現在、Worker のプロセス死亡（crash-detect.sh）しか検知できない。chain 停止・エラー出力・input-waiting 長時間継続といった「論理的異常」は見逃され、Worker が無駄にタイムアウトまで放置される。/observe パターン（tmux capture-pane + AI 分析）を Pilot のポーリングループに組み込むことで、早期異常検知→Issue 提案の自動化サイクルを実現する。

## What Changes

- `commands/autopilot-phase-execute.md` に health check ステップを追加（sequential/parallel 両モード）
- Worker 異常パターン検知の定義（3パターン: chain 停止、エラー出力、input-waiting 長時間）
- 検知時のレポート出力先 `.autopilot/health-reports/` の新設
- Issue Draft テンプレート生成（`gh issue create` は実行しない、提案のみ）
- `deps.yaml` の autopilot-phase-execute calls セクション更新

## Capabilities

### New Capabilities

- **proactive-health-check**: Pilot ポーリングループ内で Worker の論理的異常を検知
  - chain 停止: state-read の最終更新から N 分経過（デフォルト 10 分、設定可能）
  - エラー出力: tmux capture-pane でエラーパターン検出
  - input-waiting 長時間: session-state.sh で input-waiting が 5 分以上継続
- **health-report**: 異常検知時に `.autopilot/health-reports/` へ構造化レポートを出力
- **issue-draft**: レポートに Issue Draft テンプレート（タイトル・概要・再現状況）を含める

### Modified Capabilities

- **autopilot-phase-execute**: poll ループ内に health check ステップを挿入（crash-detect との重複なし）
- **deps.yaml**: autopilot-phase-execute の calls セクションに外部依存（session-comm.sh capture）を追加

## Impact

- **変更対象**: `commands/autopilot-phase-execute.md`, `deps.yaml`
- **新規ファイル**: health check ロジック用スクリプト（`.autopilot/health-reports/` ディレクトリは実行時に自動作成）
- **外部依存**: `/observe` スキル（ubuntu-note-system env プラグイン）、`session-comm.sh capture`（#78 で統合済み前提）
- **既存機能との境界**: crash-detect = プロセス死亡検知（既存）、本 Issue = 論理的異常検知（新規）。重複なし
