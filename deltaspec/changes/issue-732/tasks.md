## 1. AC 1: autopilot-init.sh 完了済みセッション自動削除

- [ ] 1.1 `is_session_completed()` に issues フィールド空ガード（`length == 0` → false）を追加
- [ ] 1.2 L82 の前に `is_session_completed()=true` → 自動削除分岐を挿入（session.json + issues/issue-*.json 削除）
- [ ] 1.3 受け入れテスト: 全 issue done の session.json で `--force` なし実行 → exit 0 + session.json 削除を確認
- [ ] 1.4 受け入れテスト: issues=[] の session.json → exit 1 を確認
- [ ] 1.5 受け入れテスト: running issue ありの session.json → exit 1 を確認

## 2. AC 3: orchestrator ログ per-session 分離

- [ ] 2.1 `autopilot-pilot-wakeup-loop.md` L22-24 に SESSION_ID 取得処理を追加（jq + unknown フォールバック + WARN 出力）
- [ ] 2.2 `_ORCH_LOG` を `orchestrator-phase-${PHASE_NUM}-${SESSION_ID}.log` に変更
- [ ] 2.3 `autopilot-orchestrator.sh` のログ書き込み先を session_id 付き命名に統一（`grep -n` で現在行を確認してから編集）
- [ ] 2.4 wakeup-loop.md L48 の grep パターンを `orchestrator-phase-${PHASE_NUM}-*.log` ワイルドカードに更新
- [ ] 2.5 `orchestrator-nohup-trace.bats` L140, L164-228 のログ名照合をワイルドカードに更新
- [ ] 2.6 `architecture/domain/contexts/autopilot.md` L348, L358 のログ path 記述を新命名規則に更新
- [ ] 2.7 受け入れテスト: 2 連続 Wave 起動後 trace/ に session_id が異なる 2 ファイルが存在することを確認
- [ ] 2.8 受け入れテスト: bats テスト `orchestrator-nohup-trace.bats` が全てパスすることを確認

## 3. AC 4: L26 再修正防止マーカー

- [ ] 3.1 `autopilot-pilot-wakeup-loop.md` の `## Step A` ヘッダとコードブロック開始の間に HTML コメントと blockquote 形式の HOTFIX #732 警告を挿入
- [ ] 3.2 受け入れテスト: `grep -c "HOTFIX #732" plugins/twl/commands/autopilot-pilot-wakeup-loop.md` = 2 を確認
