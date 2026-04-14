## Why

`twl spec new` コマンドは `issue:`, `name:`, `status:` フィールドを `.deltaspec.yaml` に自動書き込みするが、`change-propose.md` の Step 0 auto_init フローにはこれと重複する `echo` 補完処理が残存しており、ファイルへの重複エントリ書き込みを引き起こす。

## What Changes

- `plugins/twl/commands/change-propose.md` Step 0 の `.deltaspec.yaml` 補完用 echo 2 行（`name:` と `status:`）を削除する
- `twl spec new` 呼出直後に「`twl spec new` が自動補完する（issue 番号・name・status）」のコメントを追加する

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `change-propose.md` Step 0 auto_init フロー: `twl spec new` に補完を一任し、echo による手動補完を廃止する

## Impact

- `plugins/twl/commands/change-propose.md`（Step 0、40-46 行付近）
- 機能的影響なし（冗長処理の除去のみ）
- 依存コンポーネントへの破壊的変更なし
