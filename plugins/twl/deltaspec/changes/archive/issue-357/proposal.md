## Why

`co-observer` コンポーネントは `su-observer`（Supervisor-Observer）にリネームされ、役割が supervisor 層へ昇格した。しかし `plugins/twl/deps.yaml` の関連エントリ（components セクション、entry_points、calls 参照）がまだ古い `co-observer` 名を参照しており、`twl check` でエラーが発生するため一貫性を回復する必要がある。

## What Changes

- `plugins/twl/deps.yaml`: `co-observer` コンポーネントエントリを `su-observer` にリネーム
  - `type: controller` → `type: supervisor` に変更
  - `entry_points` の `skills/co-observer/SKILL.md` → `skills/su-observer/SKILL.md` に更新
  - `co-autopilot` セクション内の `calls` にある `controller: co-observer` → `controller: su-observer` に更新
  - `#310` コメント等の `co-observer` 参照をすべて `su-observer` に更新
  - `supervises: [co-autopilot, co-issue, co-architect, co-project, co-utility]` リストを引き継ぐ

## Capabilities

### New Capabilities

なし（リネーム・型変更のみ）

### Modified Capabilities

- **su-observer エントリ**: deps.yaml において `su-observer` が `type: supervisor` として正式に登録される
- **co-autopilot 参照**: `co-autopilot` の `calls` セクションが正しく `su-observer` を参照するようになる

## Impact

- `plugins/twl/deps.yaml`（単一ファイルの編集）
- `twl check` / `twl update-readme` の正常完了
