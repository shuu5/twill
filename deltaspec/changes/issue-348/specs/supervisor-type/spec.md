## RENAMED Requirements

### Requirement: types.yaml の observer 型を supervisor に rename

`cli/twl/types.yaml` において `observer` 型定義を `supervisor` に完全置換しなければならない（SHALL）。`can_supervise: [controller]` が維持され、`spawnable_by` は ADR-014 準拠の `[user]` のみとしなければならない（SHALL）。

#### Scenario: types.yaml supervisor 型定義
- **WHEN** `cli/twl/types.yaml` を読み込む
- **THEN** `supervisor` キーが存在し、`observer` キーが存在しない

#### Scenario: types.yaml spawnable_by 更新
- **WHEN** `atomic`、`specialist`、`reference` 型の `spawnable_by` を確認する
- **THEN** `supervisor` が列挙され `observer` が存在しない

#### Scenario: can_supervise 維持
- **WHEN** `supervisor` 型定義を確認する
- **THEN** `can_supervise: [controller]` が設定されている

## MODIFIED Requirements

### Requirement: types.py の observer 参照を supervisor に更新

`cli/twl/src/twl/core/types.py` 内の全 `observer` 参照を `supervisor` に更新しなければならない（SHALL）。`_FALLBACK_TOKEN_THRESHOLDS`、`_FALLBACK_TYPE_RULES`、`known_order`、`valid_types` が対象である。

#### Scenario: _FALLBACK_TOKEN_THRESHOLDS 更新
- **WHEN** `_FALLBACK_TOKEN_THRESHOLDS` を参照する
- **THEN** `supervisor` キーが存在し `observer` キーが存在しない

#### Scenario: _FALLBACK_TYPE_RULES 更新
- **WHEN** `_FALLBACK_TYPE_RULES` を参照する
- **THEN** `supervisor` キーが存在し `observer` キーが存在しない

#### Scenario: known_order 更新
- **WHEN** `print_rules()` が呼ばれる
- **THEN** `known_order` に `supervisor` が含まれ `observer` が含まれない

#### Scenario: valid_types 更新
- **WHEN** `sync_check()` が呼ばれる
- **THEN** `valid_types` に `supervisor` が含まれ `observer` が含まれない

### Requirement: validate.py の observer 参照を supervisor に更新

`cli/twl/src/twl/validation/validate.py` 内の `observer` 参照を `supervisor` に更新しなければならない（SHALL）。L95 のセクション判定と `v3_type_keys` が対象である。

#### Scenario: セクション判定更新
- **WHEN** validate.py のセクション判定マップを参照する
- **THEN** `supervisor` → `skills` のマッピングが存在し `observer` が存在しない

#### Scenario: v3_type_keys 更新
- **WHEN** v3 型キーセットを参照する
- **THEN** `supervisor` が含まれ `observer` が含まれない

### Requirement: graph.py の observer 分類ロジックを supervisor に更新

`cli/twl/src/twl/core/graph.py` 内の `observers` キーおよび `observer` 分岐を `supervisors`/`supervisor` に更新しなければならない（SHALL）。

#### Scenario: グラフキー更新
- **WHEN** グラフ分析結果を参照する
- **THEN** `supervisors` キーが存在し `observers` キーが存在しない

#### Scenario: 分類ロジック更新
- **WHEN** `supervisor` 型のスキルが分析される
- **THEN** `result['supervisors']` に追加される

## ADDED Requirements

### Requirement: twl check が PASS する

全変更適用後、`twl check` コマンドが PASS しなければならない（SHALL）。`observer` 未定義エラーが発生してはならない。

#### Scenario: twl check PASS
- **WHEN** `twl check` を実行する
- **THEN** エラーなしで PASS する

#### Scenario: supervisor 型の twl check 認識
- **WHEN** `supervisor` 型を使用するコンポーネントに対して `twl check` を実行する
- **THEN** 型バリデーションエラーが発生しない
