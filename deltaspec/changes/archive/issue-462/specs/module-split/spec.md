## ADDED Requirements

### Requirement: mergegate_guards モジュール
`twl.autopilot.mergegate_guards` モジュールを新規作成し、`self` 非依存の guard 関数群を収容しなければならない（SHALL）。

#### Scenario: guard 関数のインポート
- **WHEN** `from twl.autopilot.mergegate_guards import _check_phase_review_guard` を実行する
- **THEN** インポートが成功し、関数が呼び出し可能である

#### Scenario: deps.yaml 登録
- **WHEN** `twl check` を実行する
- **THEN** `autopilot-mergegate-guards` エントリが deps.yaml に存在し、エラーが発生しない

### Requirement: mergegate.py の行数削減
`cli/twl/src/twl/autopilot/mergegate.py` の行数は 500 行以下でなければならない（MUST）。Phase A（guard 抽出）後に測定し、超過する場合は Phase B を実施する。

#### Scenario: Phase A 後の行数確認
- **WHEN** `wc -l cli/twl/src/twl/autopilot/mergegate.py` を実行する
- **THEN** 行数が 500 以下である

### Requirement: 公開 API の不変性
`MergeGate` クラスの公開メソッド（`execute`, `reject`, `reject_final`, `from_env`）のシグネチャおよび動作は不変でなければならない（MUST）。

#### Scenario: 既存テスト通過
- **WHEN** `pytest cli/twl/tests/test_autopilot_mergegate.py cli/twl/tests/autopilot/test_merge_gate_phase_review.py` を実行する
- **THEN** 全テストが PASSED であり、FAILED が 0 件である

### Requirement: テストのインポートパス更新
`test_merge_gate_phase_review.py` の `_check_phase_review_guard` インポートは `twl.autopilot.mergegate_guards` から行わなければならない（SHALL）。

#### Scenario: テストファイルのインポートパス
- **WHEN** `test_merge_gate_phase_review.py` を inspect する
- **THEN** `from twl.autopilot.mergegate_guards import _check_phase_review_guard` が含まれる
