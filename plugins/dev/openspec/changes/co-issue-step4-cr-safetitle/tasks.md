## 1. SKILL.md 修正

- [x] 1.1 `skills/co-issue/SKILL.md` L249-254 のセキュリティ注意セクションの説明文を allow-list 方式（`LC_ALL=C tr -cd '[:alnum:][:space:]._-'`）に更新
- [x] 1.2 `skills/co-issue/SKILL.md` L264 の SAFE_TITLE 定義を `tr -d '...'` から `LC_ALL=C tr -cd '[:alnum:][:space:]._-'` に変更

## 2. 検証

- [x] 2.1 変更後の SAFE_TITLE がバッククォート・`$`・`!` を除去することを確認（例: `echo 'title with ! and $' | LC_ALL=C tr -cd '[:alnum:][:space:]._-'`）
- [x] 2.2 `[Feature]` プレフィックスを含む英語タイトルが適切に保持されることを確認
