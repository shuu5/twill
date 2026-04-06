## 1. project-board-archive.sh 修正

- [x] 1.1 `scripts/project-board-archive.sh` line 68 の `PROJECT_NUMBERS` 取得部分を `mapfile -t PROJECT_NUMS < <(...)` に置換
- [x] 1.2 `for PROJECT_NUM in $PROJECT_NUMBERS` を `for PROJECT_NUM in "${PROJECT_NUMS[@]}"` に置換

## 2. project-board-backfill.sh 修正

- [x] 2.1 `scripts/project-board-backfill.sh` line 74 の `PROJECT_NUMBERS` 取得部分を `mapfile -t PROJECT_NUMS < <(...)` に置換
- [x] 2.2 `for PROJECT_NUM in $PROJECT_NUMBERS` を `for PROJECT_NUM in "${PROJECT_NUMS[@]}"` に置換

## 3. chain-runner.sh 修正（2箇所）

- [x] 3.1 `scripts/chain-runner.sh` line 209 の `project_numbers` 取得部分を `mapfile -t project_nums < <(...)` に置換
- [x] 3.2 `for PROJECT_NUM in $project_numbers`（line 209付近）を `for PROJECT_NUM in "${project_nums[@]}"` に置換
- [x] 3.3 `scripts/chain-runner.sh` line 344 の同様のパターンを同じく `mapfile` パターンに置換

## 4. autopilot-plan-board.sh 修正

- [x] 4.1 `scripts/autopilot-plan-board.sh` line 39 の `project_numbers` 取得部分を `mapfile -t project_nums < <(...)` に置換
- [x] 4.2 `for PROJECT_NUM in $project_numbers` を `for PROJECT_NUM in "${project_nums[@]}"` に置換
- [x] 4.3 line 40-41 の数値バリデーションガード `[[ ! "$pnum" =~ ^[0-9]+$ ]] && continue` が維持されていることを確認

## 5. 検証

- [x] 5.1 4スクリプトに対して `shellcheck` を実行し word-split WARNING がゼロであることを確認
- [x] 5.2 `loom check` が PASS することを確認
