## Why

ADR-014 で `observer` 型を `supervisor` 型に再定義し、`cli/twl/types.yaml` および Python ソースコードは既に置換済み（Issue #348）だが、`cli/twl/tests/` 内のテストファイルに `observer` 参照が残存している。型システムの一貫性を保つため、テストコードも `supervisor` に完全置換する必要がある。

## What Changes

- `cli/twl/tests/test_observer_type.py`: ファイルを `test_supervisor_type.py` にリネーム
- テストクラス名・docstring の `observer` → `supervisor` 置換
- `spawnable_by` assertion から `launcher` を除去し、`[user]` のみに変更（ADR-014 準拠）
- 型名参照 (`observer`) を `supervisor` に置換

## Capabilities

### Modified Capabilities

- テストスイートが `supervisor` 型を正しく検証する
- `pytest tests/` が全件 PASS する（`observer` 未定義エラーなし）

## Impact

- `cli/twl/tests/test_observer_type.py`（リネーム → `test_supervisor_type.py`、型名・assertion 更新）
