## Why

deps.yaml v3.0 で導入された chain/step 双方向参照（`chains.steps` ⟺ `component.chain`、`parent.calls[].step` ⟺ `child.step_in`）は、AI による編集時に片方だけ更新され不整合が生じるリスクがある。現在の `validate_v3_schema` は構文レベルの検証のみで、双方向整合性やチェーン参加者の型制約は検証していない。

## What Changes

- `twl-engine.py` に `chain_validate(deps, plugin_root)` 関数を追加
- `chains.steps` ⟺ `component.chain` の双方向一致検証
- `parent.calls[].step` ⟺ `child.step_in` の双方向一致検証
- Chain 参加者の型制約検証（Chain A: workflow|atomic、Chain B: atomic|composite）
- `calls` 内 step 番号の昇順検証
- プロンプト body 内の chain/step 参照と deps.yaml の整合性検証
- `twl check` 実行時に v3.0 deps.yaml を検出した場合に自動実行

## Capabilities

### New Capabilities

- **chain-bidirectional**: `chains.steps` と `component.chain` の双方向整合性検証
- **step-bidirectional**: `parent.calls[].step` と `child.step_in` の双方向整合性検証
- **chain-type-guard**: Chain 種別ごとの参加者型制約検証
- **step-ordering**: calls 内 step 番号の昇順検証
- **prompt-consistency**: body 内の chain/step 参照と deps.yaml の整合性検証

### Modified Capabilities

- **twl check**: v3.0 deps.yaml 検出時に chain 検証を自動統合

## Impact

- **変更ファイル**: `twl-engine.py`（chain_validate 関数追加 + check コマンド統合）
- **テスト**: `tests/` に chain 検証用テストケース追加
- **CLI**: `twl` ラッパーへの変更なし（engine 内で統合）
- **依存関係**: #11（deps.yaml v3.0 スキーマ拡張）が前提
