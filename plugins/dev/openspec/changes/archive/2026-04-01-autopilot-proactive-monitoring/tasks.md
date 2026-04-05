## 1. health-check スクリプト作成

- [x] 1.1 `scripts/health-check.sh` を新規作成（引数: --issue, --window）
- [x] 1.2 chain 停止検知: state-read.sh の updated_at と現在時刻を比較、DEV_HEALTH_CHAIN_STALL_MIN（デフォルト 10 分）超過で検知
- [x] 1.3 エラー出力検知: `tmux capture-pane -t "$WINDOW_NAME" -p -S -50` でエラーパターン grep
- [x] 1.4 input-waiting 検知: session-state.sh 存在時のみ、DEV_HEALTH_INPUT_WAIT_MIN（デフォルト 5 分）超過で検知
- [x] 1.5 session-state.sh 非存在時のフォールバック（input-waiting スキップ）

## 2. health-report 出力

- [x] 2.1 `.autopilot/health-reports/` ディレクトリ自動作成（mkdir -p）
- [x] 2.2 レポートファイル生成: `issue-{N}-{YYYYMMDD-HHMMSS}.md` 形式
- [x] 2.3 レポート内容: 検知パターン種別、検知時刻、tmux capture-pane 出力（50 行）
- [x] 2.4 Issue Draft テンプレート生成（タイトル、概要、再現状況、対応候補）

## 3. autopilot-phase-execute 統合

- [x] 3.1 sequential モード: poll ループ内に health-check.sh 呼び出し追加（running かつ crash-detect 非検知時）
- [x] 3.2 parallel モード: バッチ内各 Issue に対して health-check.sh 呼び出し追加
- [x] 3.3 health check 異常検知時: WARNING ログ出力 + health-report 生成（Worker 停止・ステータス変更は行わない）

## 4. deps.yaml 更新と検証

- [x] 4.1 autopilot-phase-execute の calls セクションに `script: health-check` を追加
- [x] 4.2 外部依存（session-state.sh, session-comm.sh）の optional 記載追加
- [x] 4.3 `loom check` が PASS することを確認
