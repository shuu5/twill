<!-- Note: 全タスクは Issue #348 PR (#392) の中で実施・マージ済み（origin/main で確認済み）。本 DeltaSpec は事後記録として作成。 -->

## 1. テストファイルのリネームと更新

- [x] 1.1 `cli/twl/tests/test_observer_type.py` を `test_supervisor_type.py` にリネームする
- [x] 1.2 テストクラス名・docstring の `observer` → `supervisor` 置換する
- [x] 1.3 `spawnable_by` assertion から `launcher` を除去する（ADR-014 準拠: `spawnable_by: [user]` のみ）
- [x] 1.4 型名参照 (`observer`) を `supervisor` に置換する

## 2. 検証

- [x] 2.1 `pytest tests/test_supervisor_type.py` を実行して全 24 テストが PASS することを確認する
- [x] 2.2 全 AC チェックボックスを満たすことを確認する
