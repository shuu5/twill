## 1. deps.yaml 編集

- [x] 1.1 `plugins/twl/deps.yaml` の `co-observer` コンポーネントエントリを `su-observer` にリネーム
- [x] 1.2 `type: controller` を `type: supervisor` に変更
- [x] 1.3 `supervises: [co-autopilot, co-issue, co-architect, co-project, co-utility]` リストを引き継ぐ
- [x] 1.4 `entry_points` の `skills/co-observer/SKILL.md` → `skills/su-observer/SKILL.md` に更新
- [x] 1.5 `co-autopilot` の `calls` 内 `co-observer` 参照 → `su-observer` に更新（参照なし、対応不要）
- [x] 1.6 コメント行の `co-observer` 参照をすべて `su-observer` に更新

## 2. 検証

- [x] 2.1 `twl check` を実行し PASS を確認
- [x] 2.2 `twl update-readme` を実行し正常完了を確認
