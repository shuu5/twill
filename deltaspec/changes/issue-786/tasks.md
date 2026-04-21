## 1. issue-729 artifacts 完成

- [ ] 1.1 `deltaspec/changes/issue-729/proposal.md` を design.md の内容（SESSION_ID path-traversal サニタイズ）から作成
- [ ] 1.2 `deltaspec/changes/issue-729/specs/supervisor-hooks.md` を作成（SU-9 ADDED 要件）
- [ ] 1.3 `deltaspec/changes/issue-729/tasks.md` を作成
- [ ] 1.4 `twl spec status "issue-729" --json` で isComplete=true を確認

## 2. DeltaSpec archive（順次適用）

- [ ] 2.1 `twl spec archive "issue-725" -y` を実行し spec 統合完了を確認
- [ ] 2.2 `twl spec archive "issue-729" -y` を実行し spec 統合完了を確認
- [ ] 2.3 `twl spec archive "issue-732" -y` を実行し spec 統合完了を確認
- [ ] 2.4 `twl spec archive "issue-740" -y` を実行し spec 統合完了を確認

## 3. 検証

- [ ] 3.1 `twl spec validate --all` で全 change がエラーなしであることを確認
- [ ] 3.2 `twl validate` を実行し PASS を確認
- [ ] 3.3 bats テストを実行し全 PASS を確認（`cd plugins/twl && bats tests/`）

## 4. クロスリファレンス

- [ ] 4.1 Issue #725 に「DeltaSpec archived in PR #N」コメントを追加
- [ ] 4.2 Issue #729 に「DeltaSpec archived in PR #N」コメントを追加
- [ ] 4.3 Issue #732 に「DeltaSpec archived in PR #N」コメントを追加
- [ ] 4.4 Issue #740 に「DeltaSpec archived in PR #N」コメントを追加

## 5. issue-786 DeltaSpec 自身の後処理

- [ ] 5.1 `twl spec archive "issue-786" --skip-specs -y` を実行
