## Why

`plugins/twl/CLAUDE.md` の「Controller は7つ」記述が、ADR-014 で確定した設計（Controller は6つ + Supervisor は1つ）に追従していない。`co-observer` は `su-observer`（Supervisor 型）に改名されたが、CLAUDE.md には旧名のまま Controller として列挙されており、LLM のセッション起動時に参照されると ADR-014 の設計意図と矛盾する。

## What Changes

- `plugins/twl/CLAUDE.md` の「Controller は7つ」→「Controller は6つ」に変更
- Controller テーブルから `co-observer` 行を削除
- Controller テーブルの後に「Supervisor は1つ」セクションを追加
- `su-observer`（Supervisor 型）を別テーブルで記載

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **CLAUDE.md ドキュメント**: Controller/Supervisor の区別が ADR-014 の設計と一致

## Impact

- `plugins/twl/CLAUDE.md` のみ変更（ドキュメント更新のみ）
- コード実装への影響なし
