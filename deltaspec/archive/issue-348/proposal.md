## Why

ADR-014 で `observer` 型を `supervisor` 型に再定義したが、`cli/twl/types.yaml` および関連する Python ソースコードに `observer` 参照が残存している。型システムの一貫性を保つため、全 `observer` 参照を `supervisor` に完全置換する必要がある。

## What Changes

- `cli/twl/types.yaml`: `observer` 型定義を `supervisor` に rename。`spawnable_by` 内の全 `observer` 参照を `supervisor` に置換（atomic, specialist, reference 型が対象）
- `cli/twl/src/twl/core/types.py`: `_FALLBACK_TYPE_RULES` (L34)、`_FALLBACK_TOKEN_THRESHOLDS` (L23)、`print_rules()` の `known_order` (L137)、`sync_check()` の `valid_types` (L184) の observer → supervisor
- `cli/twl/src/twl/validation/validate.py`: observer セクション判定 (L95)、`v3_type_keys` (L267) の observer → supervisor
- `cli/twl/src/twl/core/graph.py`: `observers` キー (L150)、`observer` 分岐 (L168-169) の supervisor 対応

## Capabilities

### New Capabilities

- `supervisor` 型が types.yaml で正式定義される
- `can_supervise: [controller]` が supervisor 型に設定される

### Modified Capabilities

- `spawnable_by` の `observer` 参照がすべて `supervisor` に更新される（atomic, specialist, reference 型）
- Python コア実装の型列挙・バリデーションが `supervisor` に対応する
- `twl check` が observer 未定義エラーなしに PASS する

## Impact

- `cli/twl/types.yaml`（型定義ファイル）
- `cli/twl/src/twl/core/types.py`（フォールバック型ルール・バリデーション）
- `cli/twl/src/twl/validation/validate.py`（型バリデーション）
- `cli/twl/src/twl/core/graph.py`（グラフ分類ロジック）
- `spawnable_by: [launcher]` を削除し、ADR-014 準拠の `spawnable_by: [user]` のみに変更
