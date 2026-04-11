## Why

`plugins/twl/skills/su-observer/SKILL.md` の Step 6 に compact モードの詳細が不足しており、su-compact コマンドへの委譲方法や SU-5/SU-6 制約が明文化されていない。これにより Observer が compact モードをいつ・どのように実行すべきかが不明確となっている。

## What Changes

- `plugins/twl/skills/su-observer/SKILL.md`
  - Step 6（compact モード）に su-compact コマンドの呼び出し詳細を追加
  - context 50% 自動監視（SU-5 制約）の記述を追加
  - Wave 完了時の自動 compaction（SU-6 制約）の記述を追加
  - su-compact コマンドの呼出シグネチャ（`/su-compact`、`--wave`、`--task`、`--full`）を明記

## Capabilities

### New Capabilities

なし（SKILL.md のドキュメント追記のみ）

### Modified Capabilities

- **su-observer Step 6**: compact モードの詳細が明文化される
  - su-compact コマンドへの委譲フローが明記される
  - SU-5（context 50% 閾値自動監視）制約が記述される
  - SU-6（Wave 完了時自動 compaction）制約が記述される
  - 各呼出パターン（`--wave`、`--task`、`--full`）の使用条件が明記される

## Impact

- 影響ファイル: `plugins/twl/skills/su-observer/SKILL.md` のみ
- API/依存変更なし
- 実装コードの変更なし（ドキュメント追記のみ）
