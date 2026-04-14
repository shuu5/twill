## Why

`twl --validate` が 13 件の型ルール違反を報告しており、Issue C（git commit gate）の前提条件として全違反を解消する必要がある。違反は 3 グループ（types.yaml ルール不足、validate.py の plugin キー未対応、chain-steps.sh の名前不一致）に分類され、最小限の修正で解消できる。

## What Changes

- `cli/twl/types.yaml`: controller 型の `spawnable_by` に `supervisor` 追加、`can_spawn` に `controller` 追加（ADR-014 の su-observer spawn 許可）
- `cli/twl/types.yaml`: atomic 型の `spawnable_by` に `user` 追加、`can_spawn` に `atomic` 追加（su-compact → externalize-state の spawn 許可）
- `cli/twl/src/twl/validation/validate.py`: v3-calls-key チェックの除外キーに `plugin` を追加（クロスプラグイン参照メタ情報）
- `plugins/twl/scripts/chain-steps.sh`: `board-status-update` → `project-board-status-update` に統一（deps.yaml 側の名前に合わせる）

## Capabilities

### New Capabilities

なし（既存動作の型ルール整合のみ）

### Modified Capabilities

- **twl --validate**: 13 件の違反が解消され `Violations: 0` を返すようになる
- **controller 型の spawn**: su-observer からの controller spawn が型ルール上で有効になる
- **atomic 型の spawn**: su-compact から externalize-state（atomic）への spawn が型ルール上で有効になる
- **v3-calls-key チェック**: plugin キーを持つ calls エントリが誤検知されなくなる
- **chain-step-sync チェック**: board-status-update の名前不一致が解消される

## Impact

- **影響ファイル**: `cli/twl/types.yaml`、`cli/twl/src/twl/validation/validate.py`、`plugins/twl/scripts/chain-steps.sh`
- **スコープ外**: types.yaml の大規模リファクタリング、hook の追加（Issue A/B/C/D）
- **破壊的変更なし**: deps.yaml 側のコンポーネント宣言は変更しない
