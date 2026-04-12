## 1. types.yaml: controller 型ルール修正（違反 1-3）

- [x] 1.1 `cli/twl/types.yaml` の controller 型の `spawnable_by` に `supervisor` を追加する（`[user, launcher]` → `[user, launcher, supervisor]`）
- [x] 1.2 `cli/twl/types.yaml` の controller 型の `can_spawn` に `controller` を追加する（`[workflow, atomic, composite, specialist, reference, script]` → `[..., controller]`）

## 2. types.yaml: atomic 型ルール修正（違反 4-7）

- [x] 2.1 `cli/twl/types.yaml` の atomic 型の `spawnable_by` に `user` を追加する（`[workflow, controller, supervisor]` → `[..., user]`）
- [x] 2.2 `cli/twl/types.yaml` の atomic 型の `can_spawn` に `atomic` を追加する（`[reference, script]` → `[..., atomic]`）

## 3. validate.py: plugin キー除外（違反 8-11）

- [x] 3.1 `cli/twl/src/twl/validation/validate.py` の v3-calls-key チェックで除外キーリスト（`call_keys`）に `plugin` を追加する

## 4. chain-steps.sh: ステップ名統一（違反 12-13）

- [x] 4.1 `plugins/twl/scripts/chain-steps.sh` の `CHAIN_STEP_DISPATCH` 連想配列の `board-status-update` キーを `project-board-status-update` に変更する
- [x] 4.2 `plugins/twl/scripts/chain-steps.sh` の `CHAIN_STEP_WORKFLOW`/`CHAIN_STEP_COMMAND` 等の関連エントリも同様に `project-board-status-update` に統一する

## 5. 動作確認

- [x] 5.1 `twl --validate` を実行し `Violations: 0` を確認する
- [x] 5.2 `twl --check` の結果が悪化していないことを確認する（Missing: 0 維持）
