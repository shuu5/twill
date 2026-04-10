## 1. SKILL.md 参照更新

- [ ] 1.1 `plugins/twl/skills/co-self-improve/SKILL.md` の全 `co-observer` 参照を `su-observer` に更新（L5, L7, L13, L20, L27, L28, L41, L47, L49）
- [ ] 1.2 frontmatter `spawnable_by: [co-observer]` → `spawnable_by: [su-observer]` 変更を確認
- [ ] 1.3 DEPRECATED セクション「co-observer の supervise モード」→「su-observer の supervise モード」変更を確認

## 2. deps.yaml 更新

- [ ] 2.1 `deps.yaml` の `co-self-improve` エントリ `spawnable_by` を `su-observer` に更新

## 3. 検証

- [ ] 3.1 `grep -r "co-observer" plugins/twl/skills/co-self-improve/` で残存参照がないことを確認
- [ ] 3.2 `twl --validate` または `twl --check` でバリデーション通過を確認
