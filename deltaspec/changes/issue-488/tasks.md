## 1. deps.yaml 修正

- [x] 1.1 `plugins/twl/deps.yaml` の co-autopilot エントリ `spawnable_by` を `[user]` → `[user, su-observer]` に変更する

## 2. 整合性検証

- [x] 2.1 `twl check` を実行して PASS を確認する
- [x] 2.2 `twl update-readme` を実行して README への反映が必要か確認する（差分あれば commit）
