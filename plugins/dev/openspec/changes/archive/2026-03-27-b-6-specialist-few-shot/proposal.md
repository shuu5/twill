## Why

旧 dev plugin の 27 specialist 調査で、共通出力スキーマ（ADR-004）を実装している specialist が 0 個、severity が 6 パターン混在、confidence 値を含める形式指定が 2 specialist のみという問題が判明した。merge-gate の `confidence >= 80` フィルタが機能しないため、phase-review の結果統合が AI の自由形式変換に依存している。B-6 では reference コンポーネントとして共通出力スキーマを定義し、specialist プロンプトに注入する few-shot テンプレートを作成する。

## What Changes

- `refs/ref-specialist-output-schema.md` を reference コンポーネントとして作成（JSON Schema + severity/status 定義 + 消費側パースルール）
- `refs/ref-specialist-few-shot.md` を reference コンポーネントとして作成（specialist プロンプト用 1 例テンプレート）
- `deps.yaml` に 2 つの reference エントリを追加（`refs` セクション新設）
- `output_schema: custom` 除外条件の定義

## Capabilities

### New Capabilities

- **specialist 共通出力スキーマ reference**: 全 specialist が参照する出力形式の SSOT。status (PASS/WARN/FAIL)、severity (CRITICAL/WARNING/INFO)、findings 配列の必須フィールドを定義
- **specialist few-shot テンプレート reference**: specialist プロンプトの出力セクションに注入する 1 例テンプレート。FAIL ケースを標準例として提供
- **output_schema: custom 除外ルール**: 特定の specialist が独自出力形式を使用する場合の opt-out 定義

### Modified Capabilities

- **deps.yaml 拡張**: `refs` セクションを追加し、reference コンポーネント（ref-specialist-output-schema, ref-specialist-few-shot）を管理可能にする

## Impact

- **新規ファイル**: `refs/ref-specialist-output-schema.md`, `refs/ref-specialist-few-shot.md`
- **変更ファイル**: `deps.yaml`（refs セクション追加）
- **依存**: B-1 の `architecture/contracts/specialist-output-schema.md`（設計元）、ADR-004（設計判断）
- **後続への影響**: B-5（merge-gate）が消費側パースルールを使用、C-3（Specialist 移植）が few-shot テンプレートを各 specialist に注入
