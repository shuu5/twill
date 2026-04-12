## 1. change-propose.md 修正

- [ ] 1.1 `plugins/twl/commands/change-propose.md` の Step 0 auto_init フローにある echo 2 行（`name:` / `status:` 補完）を削除する
- [ ] 1.2 `twl spec new "issue-<N>"` 呼出直後に「`twl spec new` が自動補完する（issue 番号・name・status）」のコメントを追加する

## 2. 検証

- [ ] 2.1 `deltaspec/changes/issue-448/.deltaspec.yaml` に重複エントリがないことを確認する
- [ ] 2.2 `twl spec status "issue-448"` が正常に返ることを確認する
