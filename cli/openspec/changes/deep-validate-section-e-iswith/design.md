## Context

`deep_validate()` は deps.yaml の整合性を多段階で検証する関数。section E は specialist コンポーネントの `output_schema` フィールドを検証し、`path` で指定されたファイル内の出力スキーマキーワードを確認する。現在、`path` から構築した `plugin_root / path_str` に対して `_is_within_root()` チェックが適用されていない。

`_is_within_root()` は既に `loom-engine.py:4756` で定義済みで、他の 13 箇所で使用されている。

## Goals / Non-Goals

**Goals:**

- section E の path 構築箇所に `_is_within_root()` チェックを追加
- パストラバーサルを拒否するテストを追加

**Non-Goals:**

- `_is_within_root()` 関数自体の変更
- section E 以外の検証ロジック変更
- warning メッセージの追加（既存パターンでは `_is_within_root()` 失敗時は silent skip）

## Decisions

1. **Silent skip パターンを踏襲**: `_is_within_root()` が False の場合は `continue` で静かにスキップする。既存の他セクションと同一パターン。warning を出す選択肢もあるが、既存パターンとの一貫性を優先。

2. **チェック挿入位置**: `path = plugin_root / path_str` の直後、`path.exists()` の前に配置。resolveされたパスがルート外であれば存在チェック自体を行わない。

## Risks / Trade-offs

- リスクは極めて低い。正常な deps.yaml の path はプラグインルート内を指すため、既存動作に影響なし。
- `_is_within_root()` は symlink を resolve した上で判定するため、symlink 経由のトラバーサルも防御される。
