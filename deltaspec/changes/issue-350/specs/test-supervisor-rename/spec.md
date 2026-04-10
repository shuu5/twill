## RENAMED Requirements

### Requirement: テストファイル名を supervisor に更新

`cli/twl/tests/test_observer_type.py` は `test_supervisor_type.py` にリネームされなければならない（SHALL）。

#### Scenario: テストファイルのリネーム
- **WHEN** `cli/twl/tests/` ディレクトリを確認する
- **THEN** `test_supervisor_type.py` が存在し、`test_observer_type.py` は存在しない

## MODIFIED Requirements

### Requirement: テスト内 observer 参照を supervisor に更新

テストクラス名・docstring・アサーション内の `observer` 参照はすべて `supervisor` に更新されなければならない（SHALL）。

#### Scenario: spawnable_by アサーション（launcher 除去）
- **WHEN** `supervisor` 型の `spawnable_by` をチェックするテストが実行される
- **THEN** `'launcher' not in spawnable_by` アサーションが PASS する（ADR-014 準拠）

#### Scenario: pytest 全件 PASS
- **WHEN** `pytest tests/test_supervisor_type.py` を実行する
- **THEN** 全テストが PASS し、FAIL が 0 件である
