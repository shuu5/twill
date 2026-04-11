## 1. dispatch_mode 修正

- [x] 1.1 `chain-steps.sh` の `CHAIN_STEP_DISPATCH` で `[post-change-apply]=llm` を `[post-change-apply]=runner` に変更
- [x] 1.2 `chain-runner.sh` の `post-change-apply` ケースのコメントを "runner ステップ記録" に更新

## 2. 検証

- [x] 2.1 `twl check` を実行して Critical エラーがないことを確認
- [x] 2.2 `twl --validate` を実行して違反がないことを確認
