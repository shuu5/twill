## Why

`chain generate --write` の Template B（called-by frontmatter description）書き込みが未実装。現在は called-by パターンの検出のみで、実際の description 更新が行われない（行3120-3138）。また `--check` も Template A のドリフト検出のみで Template B を検証しない。chain-driven 設計の SSOT 自動生成が不完全な状態。

## What Changes

- `chain_generate_write()` の Template B 処理を完全実装（frontmatter description への called-by 文の追記・更新）
- `chain_generate_check()` に Template B ドリフト検出を追加
- 既存 description テキストを保持しつつ、called-by 部分のみを正規表現で置換/追記するロジック

## Capabilities

### New Capabilities

- **template-b-write**: `--write` 時に frontmatter description に called-by 文を追記/更新。既存の called-by 文がある場合は正規表現で上書き、ない場合は末尾に追記
- **template-b-check**: `--check` 時に Template B（frontmatter description 内の called-by 文）のドリフトを検出し、期待値との差分を表示

### Modified Capabilities

- **chain-generate-write**: Template A のみ → Template A + B の書き込みに拡張
- **chain-generate-check**: Template A のみ → Template A + B のドリフト検出に拡張

## Impact

- **変更対象**: `twl-engine.py`（`chain_generate_write()`, `chain_generate_check()` の拡張、ヘルパー関数追加）
- **テスト追加**: Template B の write/check に対するユニットテスト
- **既存機能**: Template A の動作に影響なし
