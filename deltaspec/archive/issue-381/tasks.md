## 1. chain-runner.sh 修正

- [x] 1.1 `step_next_step()` に `mode` の state 読み込みを追加する（`is_quick` と同パターン）
- [x] 1.2 `step_next_step()` のループ内に `mode=direct` かつ `DIRECT_SKIP_STEPS` に含まれる場合の `continue` を追加する
- [x] 1.3 `step_chain_status()` に `mode` の state 読み込みを追加する
- [x] 1.4 `step_chain_status()` のループ内に `mode=direct` かつ `DIRECT_SKIP_STEPS` に含まれる場合の `⊘ ... (skipped/direct)` 表示を追加する

## 2. 検証

- [x] 2.1 `mode=direct` で `step_next_step` を呼び、`change-propose` がスキップされることを確認する（手動またはユニットテスト）
- [x] 2.2 `mode=direct` で `chain-status` を呼び、`(skipped/direct)` ラベルが表示されることを確認する
- [x] 2.3 `mode=propose` では通常動作することを確認する
