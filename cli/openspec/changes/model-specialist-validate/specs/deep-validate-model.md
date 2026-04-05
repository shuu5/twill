## ADDED Requirements

### Requirement: ALLOWED_MODELS 定数定義

twl-engine.py のモジュールレベルに `ALLOWED_MODELS = {"haiku", "sonnet", "opus"}` を定数として定義しなければならない（SHALL）。

#### Scenario: 定数が参照可能
- **WHEN** twl-engine.py をインポートする
- **THEN** ALLOWED_MODELS が set 型で `{"haiku", "sonnet", "opus"}` を含む

### Requirement: specialist の model 未宣言を WARNING で報告

deep_validate は specialist 型コンポーネントで model フィールドが未宣言の場合、WARNING を報告しなければならない（MUST）。ルールIDは `model-required` とする。

#### Scenario: model 未宣言の specialist
- **WHEN** specialist 型コンポーネントに model フィールドがない
- **THEN** `[model-required] {name}: specialist で model 未宣言` を WARNING に追加する

#### Scenario: model 宣言済みの specialist
- **WHEN** specialist 型コンポーネントに model フィールドが ALLOWED_MODELS 内の値で宣言されている
- **THEN** WARNING も INFO も報告しない

### Requirement: 未知の model 値を INFO で報告

deep_validate は specialist の model 値が ALLOWED_MODELS に含まれない場合、INFO を報告しなければならない（MUST）。タイポ検出用であり、将来の新モデル名をブロックしない。

#### Scenario: 未知の model 値
- **WHEN** specialist 型コンポーネントの model が `"sonne"` など ALLOWED_MODELS に含まれない値
- **THEN** `[model-required] {name}: model '{value}' は許可リストにありません` を INFO に追加する

### Requirement: specialist の opus 宣言を WARNING で報告

deep_validate は specialist の model が `"opus"` の場合、WARNING を報告しなければならない（MUST）。設計判断により specialist に opus は使わない。

#### Scenario: opus を宣言した specialist
- **WHEN** specialist 型コンポーネントの model が `"opus"`
- **THEN** `[model-required] {name}: specialist に opus は推奨されません` を WARNING に追加する

### Requirement: specialist 以外の型は model チェック対象外

deep_validate の model チェックは specialist 型のみを対象とし、controller, workflow, atomic, composite, reference 等はチェックしてはならない（MUST NOT）。

#### Scenario: controller に model がない場合
- **WHEN** controller 型コンポーネントに model フィールドがない
- **THEN** model-required に関する WARNING/INFO を報告しない
