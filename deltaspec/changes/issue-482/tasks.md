## 1. コマンド引数拡張

- [x] 1.1 `test-project-reset.md` に `--real-issues` フラグの引数定義を追加
- [x] 1.2 `--mode local` と `--real-issues` の相互排他チェックを実装
- [x] 1.3 `--older-than <duration>` オプションの引数解析と date コマンドによる Epoch 変換を実装

## 2. real-issues クリーンアップフロー実装

- [x] 2.1 `.test-target/config.json` から専用リポの `repo` フィールドを読み込む処理を追加
- [x] 2.2 `.test-target/loaded-issues.json` の読み込みと `--older-than` フィルタリング処理を実装
- [x] 2.3 `--dry-run` 時の削除予定リスト出力ロジックを実装
- [x] 2.4 PR close（`gh pr close`）→ Issue close（`gh issue close`）→ branch 削除（`git push origin --delete`）の順次実行フローを実装

## 3. local モード分岐整理

- [x] 3.1 Step 4（ユーザー確認）を `--mode local` 時のみ実行するよう分岐整理
- [x] 3.2 Step 5（`git reset --hard`）を `--mode local` 時のみ実行するよう分岐整理

## 4. deps.yaml 更新

- [x] 4.1 `plugins/twl/deps.yaml` の `test-project-reset` エントリの `effort` を `low` → `medium` に更新
