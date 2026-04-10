## Why

`deep_validate()` section E（Specialist 出力スキーマ検証）で、`path` フィールドから構築したファイルパスに `_is_within_root()` チェックが欠落している。`path: ../../etc/passwd` のような値でプラグインルート外のファイルを読み取れるパストラバーサルの可能性がある。他セクションでは 13 箇所で同チェックが適用済みだが、section E（line 2920）だけ欠落している。

## What Changes

- `twl-engine.py` line 2920-2922: `path.exists()` の前に `_is_within_root()` チェックを追加
- パストラバーサルを検出するユニットテストを追加

## Capabilities

### New Capabilities

- なし

### Modified Capabilities

- `deep_validate()` section E が `_is_within_root()` によるパストラバーサル防御を持つ

## Impact

- `twl-engine.py`: `deep_validate()` 内 section E の path 構築部分（1 箇所）
- テスト: パストラバーサル拒否のテストケース追加
- 既存動作への影響なし（正常な path は `_is_within_root()` を通過する）
