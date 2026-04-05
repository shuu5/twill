## 1. PreToolUse フック追加（ubuntu-note-system）

- [x] 1.1 `~/ubuntu-note-system/claude/settings.json` の `hooks.PreToolUse` 配列に Edit|Write マッチャーのフックを追加（`architecture/domain/glossary.md` をブロック）
- [x] 1.2 ubuntu-note-system リポでコミット・push し、`./scripts/deploy.sh --all` を実行してデプロイ
- [x] 1.3 フック動作確認: `architecture/domain/glossary.md` への Edit が実際にブロックされることを確認

## 2. co-issue SKILL.md 文言修正（loom-plugin-dev）

- [x] 2.1 `skills/co-issue/SKILL.md` の Step 1.5 ステップ3を修正: 「explore-summary.md から抽出した用語のうち、MUST 用語テーブルに存在しない（未登録の）用語を列挙する（部分一致・略語は除外）」

## 3. 検証

- [x] 3.1 `loom check` を実行してエラーがないことを確認
- [x] 3.2 `loom update-readme` を実行
