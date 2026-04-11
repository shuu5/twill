## 1. test-project-scenario-load.md に --real-issues フラグ追加

- [x] 1.1 引数リストに `--real-issues` と `--force` フラグを追加する
- [x] 1.2 Step 0（モード判定）を追加: `--real-issues` フラグの有無で real-issues フローと local フローを分岐させる
- [x] 1.3 `.test-target/config.json` 読み込みステップを追加し、`mode` / `repo` フィールドを取得する
- [x] 1.4 `mode != real-issues` 時のエラーメッセージを定義する

## 2. real-issues フローの実装

- [x] 2.1 二重起票ガード: `loaded-issues.json` 存在確認 + `--force` なしの場合は skip 出力して終了
- [x] 2.2 `--force` 時の既存 Issue クローズ処理（`gh issue close` ループ）
- [x] 2.3 各 `issue_template` に対して `gh issue create --repo <repo> --title <title> --body <body> --label <labels>` を実行し Issue 番号と URL を取得する
- [x] 2.4 `.test-target/loaded-issues.json` を生成する（スキーマ: scenario/repo/loaded_at/issues[]）

## 3. commit とレスポンス整合

- [x] 3.1 `loaded-issues.json` を `git add` して `git commit -m "chore(test): load real-issues <scenario>"` する
- [x] 3.2 Step 7（JSON 出力）を更新: `--real-issues` 時は `mode: "real-issues"` と `repo` フィールドを含む JSON を出力する
- [x] 3.3 `--local-only`（未指定）の動作が変わっていないことを確認する

## 4. bats テスト追加

- [x] 4.1 `test-project-scenario-load.bats` に `--real-issues` のユニットテストを追加（mock `gh` / `git`）
- [x] 4.2 `config.json` が `mode: local` の場合のエラーテストを追加
- [x] 4.3 `loaded-issues.json` 既存時の skip テストを追加
- [x] 4.4 `--force` による再起票テストを追加
