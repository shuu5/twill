## Why

`co-issue` Step 4-CR の SAFE_TITLE 生成が deny-list 方式（バッククォート・`$`・クォートのみ除去）のため、`!`（bash history expansion）などの未知のシェルメタ文字が残存し、コマンドインジェクションリスクがある。allow-list 方式に切り替えることで未知のメタ文字を網羅的に排除する。

## What Changes

- `skills/co-issue/SKILL.md` L264 の SAFE_TITLE 定義を deny-list から allow-list に変更
- `skills/co-issue/SKILL.md` L249-254 のセキュリティ注意セクション説明文を allow-list 方式に更新

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **SAFE_TITLE サニタイズ**: `tr -d '`$"'\''` → `LC_ALL=C tr -cd '[:alnum:][:space:]._-'` に変更。ASCII 英数字・スペース・ピリオド・アンダースコア・ハイフン以外を除去

## Impact

- `skills/co-issue/SKILL.md` のみ（L249-254, L264）
- deps.yaml 変更なし（コンポーネント構成に変更なし）
- L280, L328 の `${SAFE_TITLE}` 利用箇所は変数再定義により自動適用
