## 1. autopilot-plan.sh: --board モード追加

- [x] 1.1 引数解析に `--board` オプションを追加（`--explicit`/`--issues` と排他バリデーション付き）
- [x] 1.2 `fetch_board_issues()` 関数を新設: Project Board 自動検出（GraphQL + user/org フォールバック）
- [x] 1.3 `fetch_board_issues()`: `gh project item-list` で非 Done items を取得し、`content.type == Issue` でフィルタリング
- [x] 1.4 `fetch_board_issues()`: クロスリポジトリ Issue の自動解決（`content.repository` から `--repos` JSON 構築）
- [x] 1.5 `fetch_board_issues()`: Issue リストを `parse_issues()` に渡す形式に変換（単一リポジトリ: "42 43"、クロスリポ: "42 loom#56"）
- [x] 1.6 メイン case 文に `board` モードを追加

## 2. co-autopilot SKILL.md 更新

- [x] 2.1 Step 0 引数解析テーブルに `--board` パターンを追加
- [x] 2.2 Step 1 の `autopilot-plan.sh` 呼び出しに `--board` モード分岐を追加

## 3. エラーハンドリング

- [x] 3.1 Board に非 Done Issue がない場合のエラーメッセージ＋正常終了
- [x] 3.2 リポジトリにリンクされた Project が見つからない場合のエラーメッセージ

## 4. テスト・検証

- [x] 4.1 単一リポジトリの Board Issue 取得テスト
- [x] 4.2 排他バリデーション（`--board` + `--issues` 同時指定）テスト
