## 1. chain-steps.sh に post-opsx-apply ステップを追加

- [x] 1.1 `scripts/chain-steps.sh` の `CHAIN_STEPS` 配列で `opsx-apply` の直後に `post-opsx-apply` を追加する

## 2. workflow-test-ready SKILL.md の Step 4 を更新

- [x] 2.1 Step 4 の冒頭に opsx-apply 開始前の state 記録スニペット（`current_step=opsx-apply`）を追加する
- [x] 2.2 opsx-apply 完了後の IS_AUTOPILOT 判定スニペット直前に state 記録スニペット（`current_step=post-opsx-apply`）を追加する

## 3. compaction 復帰プロトコルを更新

- [x] 3.1 `workflow-test-ready` SKILL.md の compaction 復帰プロトコルの for ループに `post-opsx-apply` を追加する
- [x] 3.2 `post-opsx-apply` の recovery action（IS_AUTOPILOT 判定スニペット実行）をプロトコルに明記する
