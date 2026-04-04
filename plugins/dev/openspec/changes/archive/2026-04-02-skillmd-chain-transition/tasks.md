## 1. workflow-setup SKILL.md Step 4 修正

- [x] 1.1 `skills/workflow-setup/SKILL.md` の Step 4 に autopilot 判定 bash スニペットを追加（state-read.sh 使用）
- [x] 1.2 IS_AUTOPILOT=true 時に「即座に `/dev:workflow-test-ready` を Skill tool で実行せよ。プロンプトで停止するな」の指示を追加
- [x] 1.3 IS_AUTOPILOT=false 時の「setup chain 完了」案内メッセージを明示化

## 2. workflow-test-ready SKILL.md Step 4 修正

- [x] 2.1 `skills/workflow-test-ready/SKILL.md` の Step 4 を書き換え: opsx-apply 完了後に autopilot 判定スニペットを実行する指示を追加
- [x] 2.2 IS_AUTOPILOT=true 時に「即座に `/dev:workflow-pr-cycle --spec <change-id>` を Skill tool で実行せよ。プロンプトで停止するな」の指示を追加
- [x] 2.3 IS_AUTOPILOT=false 時の案内メッセージを明示化

## 3. opsx-apply.md Step 3 スリム化

- [x] 3.1 `commands/opsx-apply.md` の Step 3 から IS_AUTOPILOT 判定 bash スニペットを削除
- [x] 3.2 Step 3 から `/dev:workflow-pr-cycle` 呼び出しロジックを削除
- [x] 3.3 Step 3 をシンプルなチェックポイント出力（`>>> 実装完了: <change-id>` + 手動次ステップ案内）のみに書き換え

## 4. check.md チェックポイント条件付き修正

- [x] 4.1 `commands/check.md` 末尾の「チェックポイント（MUST）」に CRITICAL FAIL 条件分岐を追加
- [x] 4.2 CRITICAL FAIL なし → `/dev:opsx-apply` を Skill tool で自動実行
- [x] 4.3 CRITICAL FAIL あり → opsx-apply をスキップしてFAIL内容を報告・停止
