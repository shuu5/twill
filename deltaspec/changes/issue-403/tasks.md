## 1. chain-steps.sh 更新

- [ ] 1.1 CHAIN_STEPS 配列（pr-verify セクション）に `phase-review` と `scope-judge` を ts-preflight の後・pr-test の前に追加
- [ ] 1.2 STEP_DISPATCH_MODE マップに `[phase-review]=llm` と `[scope-judge]=llm` を追加
- [ ] 1.3 STEP_CMD マップに `[phase-review]=commands/phase-review.md` と `[scope-judge]=commands/scope-judge.md` を追加
- [ ] 1.4 CHAIN_STEP_TO_WORKFLOW マップに `[phase-review]=pr-verify` と `[scope-judge]=pr-verify` を追加

## 2. chain.py 更新

- [ ] 2.1 STEP_TO_WORKFLOW 辞書に `"phase-review": "pr-verify"` と `"scope-judge": "pr-verify"` を追加（prompt-compliance/ts-preflight の近傍に配置）

## 3. chain-runner.sh 更新

- [ ] 3.1 case 文に `phase-review)` と `scope-judge)` のハンドラを追加（change-propose と同じ llm dispatch パターン: record_current_step + ok メッセージ）
- [ ] 3.2 エラーメッセージの利用可能ステップリスト文字列に phase-review と scope-judge を追記

## 4. 自動テスト追加

- [ ] 4.1 cli/twl/tests/ で chain trace に phase-review/scope-judge の start/end イベントが記録されることを確認するテストを追加または既存テストを拡張
