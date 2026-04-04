## 1. autopilot-init.sh stale session ロジック修正

- [x] 1.1 session.json から全 issue の完了状態を判定する関数を追加（jq で issues[].status を評価）
- [x] 1.2 --force + 完了済みセッション → 経過時間に関係なく即座に削除するロジックを実装
- [x] 1.3 --force + running issue あり → 従来通り 24h 制限を維持するロジックを実装
- [x] 1.4 issues フィールド不在/空の場合を完了済みとして扱うフォールバックを追加

## 2. autopilot-init.md eval 除去

- [x] 2.1 Step 2 の `eval "$(bash autopilot-init.sh)"` を `bash autopilot-init.sh` に変更
- [x] 2.2 Step 4 の `eval "$(bash session-create.sh)"` を `bash session-create.sh` に変更し、出力からの SESSION_ID 取得方法を修正

## 3. 検証

- [x] 3.1 loom check が PASS することを確認
