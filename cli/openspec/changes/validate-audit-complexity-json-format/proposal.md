## Why

現在の twl CLI 検証コマンド（validate, audit, deep-validate, complexity, check）は全て Markdown テキスト出力のみ。loom-plugin-dev の merge-gate やスクリプトが検証結果を機械的に消費する際、Markdown パースが必要になる。設計哲学「機械的にできることは機械に任せる」に基づき、構造化 JSON 出力を提供する。

## What Changes

- 全検証コマンドに `--format json` オプションを追加
- 共通エンベロープ（command, version, plugin, items, summary, exit_code）で統一
- items 内に severity/component/message の共通フィールドを定義
- Phase 1: validate, deep-validate, check（既に構造化 return 値あり）
- Phase 2: audit, complexity（print() 分離リファクタが前提）

## Capabilities

### New Capabilities

- `--format json` オプション: 全検証コマンドで JSON 構造化出力を選択可能
- 共通エンベロープ: command, version, plugin, items, summary, exit_code の統一構造
- コマンド別 items 拡張フィールド（validate: code/rule, audit: section/value/threshold, etc.）

### Modified Capabilities

- validate: JSON 出力対応（既存テキスト出力は維持）
- deep-validate: JSON 出力対応（既存テキスト出力は維持）
- check: JSON 出力対応（既存テキスト出力は維持）
- audit: print() をデータ収集関数に分離 + JSON 出力対応
- complexity: print() をデータ収集関数に分離 + JSON 出力対応

## Impact

- **対象ファイル**: `twl-engine.py`（メインエンジン）
- **後方互換**: `--format` 未指定時は既存出力を完全維持
- **exit code**: JSON 出力でも既存と同一（violations あれば非ゼロ）
- **依存先**: shuu5/loom-plugin-dev#7（B-5: merge-gate が JSON を消費）
- **リスク**: audit/complexity の print() リファクタ（105箇所）は影響範囲が広い
