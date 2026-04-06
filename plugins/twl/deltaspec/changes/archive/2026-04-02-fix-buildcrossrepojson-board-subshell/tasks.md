## 1. _build_cross_repo_json() 修正

- [x] 1.1 `scripts/autopilot-plan-board.sh` L168: `echo "${issue_list# }"` を `BUILD_RESULT="${issue_list# }"` に変更
- [x] 1.2 L117 コメント更新: `# 出力（stdout）` を `# 出力: BUILD_RESULT グローバル変数` に変更

## 2. fetch_board_issues() 修正

- [x] 2.1 L183: `issue_list=$(_build_cross_repo_json ...)` を直接呼び出し `_build_cross_repo_json "$filtered" "$current_repo"` に変更
- [x] 2.2 L183 の次行: `issue_list="$BUILD_RESULT"` を追加

## 3. テスト追加

- [x] 3.1 `tests/bats/scripts/autopilot-plan-board-helpers.bash` にクロスリポジトリ用スタブ `_stub_gh_cross_repo_project` を追加
- [x] 3.2 `tests/bats/scripts/autopilot-plan-board-fetch.bats` にクロスリポジトリ Board テストケースを追加（plan.yaml に repos セクションが出力されることを検証）

## 4. 回帰テスト

- [x] 4.1 既存テスト `autopilot-plan-board-detect.bats` が PASS することを確認
- [x] 4.2 既存テスト `autopilot-plan-board-fetch.bats` が PASS することを確認
