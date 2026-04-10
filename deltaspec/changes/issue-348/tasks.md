## 1. types.yaml の observer → supervisor 置換

- [x] 1.1 `observer:` 型定義キーを `supervisor:` に rename する
- [x] 1.2 `spawnable_by: [user, launcher]` を `spawnable_by: [user]` に変更する（ADR-014 準拠）
- [x] 1.3 `atomic` 型の `spawnable_by` の `observer` を `supervisor` に置換する
- [x] 1.4 `specialist` 型の `spawnable_by` の `observer` を `supervisor` に置換する
- [x] 1.5 `reference` 型の `spawnable_by` の `observer` を `supervisor` に置換する

## 2. cli/twl/src/twl/core/types.py の更新

- [x] 2.1 `_FALLBACK_TOKEN_THRESHOLDS` の `'observer'` キーを `'supervisor'` に置換する（L23）
- [x] 2.2 `_FALLBACK_TYPE_RULES` の `'observer'` キーを `'supervisor'` に置換する（L34）
- [x] 2.3 `known_order` の `'observer'` を `'supervisor'` に置換する（L137）
- [x] 2.4 `valid_types` の `'observer'` を `'supervisor'` に置換する（L184）

## 3. cli/twl/src/twl/validation/validate.py の更新

- [x] 3.1 L95 のセクション判定マップの `'observer': 'skills'` を `'supervisor': 'skills'` に置換する
- [x] 3.2 `v3_type_keys` の `'observer'` を `'supervisor'` に置換する（L267）

## 4. cli/twl/src/twl/core/graph.py の更新

- [x] 4.1 `'observers': []` キーを `'supervisors': []` に置換する（L150）
- [x] 4.2 `elif skill_type == 'observer':` を `elif skill_type == 'supervisor':` に置換する（L168）
- [x] 4.3 `result['observers'].append(skill_name)` を `result['supervisors'].append(skill_name)` に置換する（L169）

## 5. 検証

- [x] 5.1 `twl check` を実行して PASS することを確認する
- [x] 5.2 全 AC チェックボックスを満たすことを確認する
