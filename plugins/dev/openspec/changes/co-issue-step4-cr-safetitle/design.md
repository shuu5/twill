## Context

`co-issue` Step 4-CR では、GitHub Issue タイトルを `gh issue create --title` に渡す際に SAFE_TITLE を生成している。現在の deny-list 方式（`tr -d '`$"'\''`）では既知のメタ文字のみ除去するため、`!` などの未知のシェルメタ文字が残存しうる。

## Goals / Non-Goals

**Goals:**
- SAFE_TITLE サニタイズを allow-list 方式に変更し、ASCII 英数字・スペース・ピリオド・アンダースコア・ハイフン以外を除去
- セキュリティ注意セクション（L249-254）の説明を allow-list 方式に更新

**Non-Goals:**
- `--body` のサニタイズ変更（既に `--body-file` 経由で安全）
- 日本語タイトル対応（`--title-file` への切り替えは別 Issue）
- deps.yaml の変更

## Decisions

### allow-list 実装: `LC_ALL=C tr -cd '[:alnum:][:space:]._-'`

```bash
# Before (deny-list)
SAFE_TITLE=$(printf '%s' "$TITLE" | tr -d '`$"'\''')

# After (allow-list)
SAFE_TITLE=$(printf '%s' "$TITLE" | LC_ALL=C tr -cd '[:alnum:][:space:]._-')
```

- `LC_ALL=C` で `[:alnum:]` を ASCII 英数字のみに限定（ロケール依存を排除）
- ピリオド・アンダースコア・ハイフンは GitHub Issue タイトルで一般的なため許可
- 日本語文字は除去されるが、`[Feature]` プレフィックスと英語概要は保持される

## Risks / Trade-offs

- **日本語タイトルの切り捨て**: 日本語のみのタイトルは空文字になる可能性があるが、co-issue が生成するタイトルは `[Type] 英語概要` 形式のため実用上問題なし
- **変更箇所が L264 のみ**: L280, L328 は `${SAFE_TITLE}` を参照するだけなので自動適用
